class ChatgptHandler < AbstractHandler
  
  require 'rubygems'
  require 'dotenv'
  require 'rest-client'
  require 'json'
  require 'pry'
  require 'colorize'
  require_relative 'helper'
  
  def initialize(api_key, assistant_id = '')
    @api_key = api_key
    @assistant_id = assistant_id
  end

  def handle(request)
    key, value = request.to_a.flatten
    case key
    when :fresh_data
      summary = {ticket_summarized: get_tickets_summary(value)}
      super(summary)
    when :to_jsonify
      puts "creando json"
      json_data = generate_json_data(value)
      #create_assistant() ... was created in the playground
      
      puts "activando asistente"
      thread = create_thread
      add_message(thread['id'], json_data) # first message, the agent must response with the function to call te template

      run = run_assistant(thread['id'])
      
      function_tool = get_response(run["id"], thread['id'])
      function_argument = function_tool['function']['arguments']

      puts "generando template"
      template = get_template(JSON.parse(function_argument))
      # show the response before continue
      # exit unless function_response.start_with?('get_template')
      # puts function_response
      # get 
      # template = eval(function_response)

      submit_tool_outputs(thread['id'], run['id'], function_tool['id'], template)

      # add_message(thread['id'], template.join("\n")) #second_message, must recieve the centra completed
      final_response = get_response(run['id'], thread['id'])

      final_response = final_response.first.gsub(/^```ruby\s*|```$/, '')
      data = {
        data: final_response,
        country: function_argument['country'],
        company: function_argument['company']
      }
      puts "template generado"
      super({ write_to_buk: data })
    end
  end

  def get_tickets_summary(tickets)
    openai_url = "https://api.openai.com/v1/chat/completions"

    payload = {
      "model": "gpt-4-turbo-preview",
      "messages": [
        {
          "role": "system",
          "content": "you will gonna receive an array with the data from tickets (in spanish). Your work is to return an json object with the following structure:\n[\n  {\n    id: Number,\n    title: String,\n    type: String[centra/bono/banco],\n    new_or_fix: String[nuevo/fix],\n    company: String,\n    country: String,\n    attached_file: String[url],\n    summary: String,\n  },\n  ...\n]\n\nattributes definition:\nid: is the same number of the ticket\ntitle: corresponds to the subject field, \n\ntype:\nthe most important attribute is the type, your work is to infers the type based in the data provided, the options are:\n\"centra\": when the ticket correspond to an accounting centralization (\"Centralización contable\" in Spanish) or accounting file.\n\"bono\": when the requirement is related to an settlement item\n\"banco\": when the ticket is related to an personalized format for a file that the bank will accept to generate payments or money transfers\n\ncompany: Is our client you can take the company name in the field custom_url_empresa or from the subdomain in the url subdomain.buk.[cl|pe|co|mx|br] \n\ncountry: this attribute could be any of this 5 options [cl|pe|co|mx|br] \n\nattached_file: is the complete GoogleDrive url that must be extracted from the desciption in the ticket \n\nsummary: The summary attribute must be short, less that 6 words.\n\nnew_or_fix: that field must be \"nuevo\" for tickets that require something new or \"fix\" if in the tickets is required some kind of modification.\n"
        },
        {
          "role": "user",
          "content": tickets.to_s
        }
      ],
      "temperature": 1,
      "max_tokens": 4096,
      "top_p": 1,
      "frequency_penalty": 0,
      "presence_penalty": 0
    }


    response = RestClient.post(openai_url, payload.to_json, {content_type: "application/json", :Authorization => "Bearer #{@api_key}"})
    content = JSON.parse(response.body)&.dig("choices",0, "message", "content")
    content = content.gsub(/^```json\s*|```$/, '')
    JSON.parse(content)
  end

  #returns Assistant ID
  def create_assistant
    create_assistant_endpoint = 'https://api.openai.com/v1/assistants'

    payload = {
      "name": "Data visualizer",
      "description": "You are great at creating beautiful data visualizations. You analyze data present in .csv files, understand trends, and come up with data visualizations relevant to those trends. You also share a brief text summary of the trends observed.",
      "model": "gpt-4-turbo-preview",
      "tools": [{"type": "code_interpreter"}],
      "file_ids": ["file-BK7bzQj3FfZFXr7DbL6xJwfo"]
    }

    response = RestClient.post(create_thread_endpoint, payload.to_json, {content_type: "application/json", :Authorization => "Bearer #{@api_key}", "OpenAI-Beta" => "assistants=v1"})

    # try to find the assistant identifier
    content = JSON.parse(response.body)
  end

  def create_thread
    create_thread_endpoint = "https://api.openai.com/v1/threads"

    payload = {}
    response = RestClient.post(create_thread_endpoint, payload.to_json, {content_type: "application/json", :Authorization => "Bearer #{@api_key}", "OpenAI-Beta" => "assistants=v1"})

    content = JSON.parse(response.body)
  end

  def add_message(thread, data)
    add_message_endpoint = "https://api.openai.com/v1/threads/#{thread}/messages"

    payload = {
      "role": "user",
      "content": data.to_s
    }

    response = RestClient.post(add_message_endpoint, payload.to_json, {content_type: "application/json", :Authorization => "Bearer #{@api_key}", "OpenAI-Beta" => "assistants=v1"})
    # JSON.parse(response.body['data'])
  end


  def submit_tool_outputs(thread_id, run_id, call_id, data)
    add_message_endpoint = "https://api.openai.com/v1/threads/#{thread_id}/runs/#{run_id}/submit_tool_outputs"

    payload = {
      "tool_outputs": [
        {
          "tool_call_id": call_id,
          "output": data.to_s
        }
      ]
    }

    response = RestClient.post(add_message_endpoint, payload.to_json, {content_type: "application/json", :Authorization => "Bearer #{@api_key}", "OpenAI-Beta" => "assistants=v1"})
    # JSON.parse(response.body['data'])
  end

  # "threads/#{thread}/messages"
  # "threads/#{thread_id}/runs"

  def generic_get(endpoint)
    path = "https://api.openai.com/v1/#{endpoint}"

    headers = {:Authorization => "Bearer #{@api_key}", "OpenAI-Beta" => "assistants=v1"}
    response = RestClient.get(path, headers)
    JSON.parse(response.body)
  end

  def get_response(run_id, thread_id)
    path = "https://api.openai.com/v1/threads/#{thread_id}/runs/#{run_id}"

    headers = {:Authorization => "Bearer #{@api_key}", "OpenAI-Beta" => "assistants=v1"}

    response = RestClient.get(path, headers)
    response_body = JSON.parse(response.body)
    status = response_body['status'] 

    if ['in_progress', 'queued'].include?(status)
      p '... :) '
      sleep(2)
      get_response(run_id, thread_id)
    elsif status == 'requires_action'
      function_tool = response_body['required_action']['submit_tool_outputs']['tool_calls'].first
      if function_tool['function']['name'] == 'get_template'
        return function_tool
      end
    elsif ['cancelling', 'cancelled', 'failed', 'expired'].include?(status)
      p " :( "
      puts "error en la respuesta del agente"
    elsif status == 'completed'
      p " :D "
      puts 'first response completed'
      messages = generic_get("threads/#{thread_id}/messages")
      
      last_response = messages["data"].map do |m|
        next unless m['role'] == 'assistant'

        m['content'].first['text']['value']
      end
      last_response.compact!

      if last_response.count != 1
        puts "El asistente respondió con más de 1 mensaje"
        return ''
      end
      last_response.flatten
    else
      puts 'algo raro pasó aquí, chao'
      exit
    end
  end

  def get_messages(thread)
    path = "https://api.openai.com/v1/threads/#{thread}/messages"

    headers = {:Authorization => "Bearer #{@api_key}", "OpenAI-Beta" => "assistants=v1"}
    params = {}

    response = RestClient.gets(path, headers: headers, params: params)
    JSON.parse(response.body)
  end

  def run_assistant(thread)
    run_assistant_endpoint = "https://api.openai.com/v1/threads/#{thread}/runs"

    payload = {
      "assistant_id": @assistant_id
    }

    response = RestClient.post(run_assistant_endpoint, payload.to_json, {content_type: "application/json", :Authorization => "Bearer #{@api_key}", "OpenAI-Beta" => "assistants=v1"})
    JSON.parse(response.body)
  end


  def generate_json_data(file_with_data)
    data = File.read(file_with_data)
    return if data.nil?
    openai_url = "https://api.openai.com/v1/chat/completions"
    payload = {
      "model": "gpt-4-turbo-preview",
      "messages": [
        {
          "role": "system",
          "content": "Your work is to generate a JSON file from the data that you receive in the prompt. Must be followed the defined structure, the separator in the data is a tabulation and the data was extracted from a xlsx file so you must have the ability to omit the tabulation when correspond.\n\nthe JSON for reference =\n{\n  \"compania\": \"String\",\n  \"pais\": \"String[Chile|Colombia|Peru|Mexico]\",\n  \"formato\": \"String[xlsx|csv|txt]\",\n  \"agrupado\": \"String[si|no]\",\n  \"archivos_separados\": \"String[si|no]\",\n  \"hojas_separadas\": \"String[si|no]\",\n  \"Detalle de centralización\":\n  {\n      \"nombre_atributo_separador\": \"String(optional)\",\n      \"Cabecera\": \"Array\",\n      \"Cuerpo\": \n      [\n        {\n          \"Nombre Campo\": \"String\", \n          \"Tipo\": \"String\",\n          \"Referencia atributo\": \"String\",\n          \"Largo (txt o csv)\": \"String\",\n          \"Atributo personalizado\": \"String\",\n          \"Formato requerido\": \"String\",\n          \"Ejemplo\": \"String\",\n          \"Detalle\": \"String\"\n        },\n        ...\n      ]\n    }\n}\n\nINPUT EXAMPLE = \n\nresumen\n\nagrupado, pais, formato, archivos_separados, nombre_atributo_separador,\nsi, chile, xlsx, no, ,\n\ndetalle\n\nNombre Campo:,Tipo:,Referencia atributo:,Largo (txt o csv):,Atributo personalizado:,Formato requerido:,Ejemplo:,Detalle:\nEXTERNAL ID,Texto,En duro,,,,NOM_NOV_2024,En el campo del cuerpo, debe imprimir la palabra NOM_MES LAS 3 PRIMERA LETRAS DE CADA MES_AÑO, Ejemplo NOM_ENE_2024, por cada registro\nID SUBSIDIARIA,Texto,Personalizado,,,ID SUBSIDIARIA,4,El campo en el cuerpo debe imprimir en cada registo lo que contegan el atributo personalizado creado en empresa llamado ID SUBSIDIARIA\nFECHA,Fecha,Por defecto,,,,1/31/2024,El campo en el cuerpo debe imprimir siempre la ultima fecha de cada mes en formato DIA/MES/AÑO Ejemplo: 31/01/2024, por cada registro\nPeríodo contable,Fecha,Por defecto,,,,ene-24,El campo en el cuerpo debe imprimir siempre el mes en minusculas y solo las 3 primeras letras mas un guion (-) y los ultimos dos digitos del año Ejemplo ene-24, por cada registro\nNOTA,Fecha,Por defecto,,,,NOM_NOV_2024_AUXILIO DE TRANSPORTE,El campo en el cuerpo debe imprimir lo de la casilla A mas el guion al piso mas el nombre del item en mayuscula, ejemplo: NOM_NOV_2024_AUXILIO DE TRANSPORTE\nID MONEDA,Texto,Por defecto,,,,2,El campo en el cuerpo debe imprimir siempre 2, por cada registro\nMONEDA,Texto,Por defecto,,,,COP,El campo en el cuerpo debe imprimir siempre la palabra: COP en mayuscula, por cada registro\nID CUENTA,Texto,Personalizado,,ID CUENTA,,3664,En el campo del cuerpo, debe imprimir el numero de ID de cuenta, por cada registro, para esto se creo el atributo personalizado en cuentas contables \nCuenta,Numero,Por defecto,,,,510506001,En el campo del cuerpo, debe imprimir la cuenta contable, teniendo en cuenta que la empresa maneja 2 tipos de planes de cuenta contables, los cuales se crearon como atributo personalizado en la sección de cuenta contable (Administrativo,Ventas). Adicional se creó un atributo personalizado en la sección de trabajos, para que el cliente le asigne el plan contable a cada empleado.\nNOMBRE CUENTA,Texto,Personalizado,,Nombre Cuenta,,SALARIOS POR PAGAR,En el campo del cuerpo, debe imprimir el Nombre de la Cuenta Contable segun corresponda, para este se creo un atributo personalizado en cuentas contables llamado: \nIMPORTE (DÉBITO),Numero,Por defecto,,,,25000,El campo en el cuerpo debe imprimir el movimiento débito sin ningún carácter especial, los campos que no tengan información deben venir en vacio\nIMPORTE (CRÉDITO),Numero,Por defecto,,,,25000,El campo en el cuerpo debe imprimir el movimiento crédito sin ningún carácter especial, los campos que no tengan información deben venir en vacio\nNOTA DE LINEA,Fecha,Por defecto,,,,NOM_NOV_2024_AUXILIO DE TRANSPORTE,El campo en el cuerpo debe imprimir lo de la casilla A mas el guion al piso mas el nombre del item en mayuscula, ejemplo: NOM_NOV_2024_AUXILIO DE TRANSPORTE….. Lo mismo de la E\nID CLASE,Texto,Por defecto,,,,,Campo debe imprimir en vacio \nCLASE,Texto,Por defecto,,,,,Campo debe imprimir en vacio \nID CATEGORIAS PRODUCTOS,Texto,Por defecto,,,,,Campo debe imprimir en vacio \nCATEGORIAS PRODUCTOS,Texto,Por defecto,,,,,Campo debe imprimir en vacio \nID DEPARTAMENTO,Texto,Personalizado,,ID Centro de Costo,,1,Debe imprimir el Id del centro de costo, para esto se creo un atributo personalizado en Seccion de Centro de costo llamado Id Centro de Costo, para que dependiendo el centro de costo que tenga el colaborador me traiga el Id Centro de Costo, adicional otro en cuentas contables llamado Centro Costo, para que el cliente indique si desea que salga centro de costo o no \nDEPARTAMENTO,Texto,Personalizado,,Nombre Centro de Costo,,2001 BODEGA - RECURSOS FISICOS,Debe imprimir el Nombre Centro de Costo, para esto se creo un atributo personalizado en Seccion de Centro de costo llamado Nombre Centro de Costo, para que dependiendo el centro de costo que tenga el colaborador me traiga el Id Centro de Costo, adicional otro en cuentas contables llamado Centro Costo, para que el cliente indique si desea que salga centro de costo o no \nID UBICACIÓN,Texto,Por defecto,,,,142,En el campo del cuerpo imprimir siempre 142 en cada registro\nUBICACIÓN,Texto,Por defecto,,,,Oficina Bogotá,En el campo del cuerpo imprimir siempre Oficina Bogotá en cada registro\nID TERCERO,Texto,Personalizado,,,,2522,Revisar archivo de Word donde se la la logica por Tablas\n\n\n\nOUTPUT EXAMPLE = \n\n{\n  \"compania\": \"NombreCliente\",\n  \"pais\": \"Colombia\",\n  \"formato\": \"xlsx\",\n  \"agrupado\": \"si\",\n  \"archivos_separados\": \"no\",\n  \"hojas_separadas\": \"no\",\n\n  \"Detalle de centralización\":\n    {\n      \"Cabecera\": \n        [\n          \"String\",\n          \"EXTERNAL ID\",\n          \"ID SUBSIDIARIA\",\n          \"FECHA\",\n          \"Período contable\",\n          \"NOTA\",\n          \"ID MONEDA\",\n          \"MONEDA\",\n          \"ID CUENTA\",\n          \"Cuenta\",\n          \"NOMBRE CUENTA\",\n          \"IMPORTE (DÉBITO)\",\n          \"IMPORTE (CRÉDITO)\",\n          \"NOTA DE LINEA\",\n          \"ID CLASE\",\n          \"CLASE\",\n          \"ID CATEGORIAS PRODUCTOS\",\n          \"CATEGORIAS PRODUCTOS\",\n          \"ID DEPARTAMENTO\",\n          \"DEPARTAMENTO\",\n          \"ID UBICACIÓN\",\n          \"UBICACIÓN\",\n          \"ID TERCERO\",\n        ],\n      \"Cuerpo\": \n      [\n        {\n          \"Nombre Campo\": \"EXTERNAL ID\", \n          \"Tipo\": \"Texto\",\n          \"Referencia atributo\": \"En duro\",\n          \"Largo (txt o csv)\": \"\",\n          \"Atributo personalizado\": \"\",\n          \"Formato requerido\": \"\",\n          \"Ejemplo\": \"NOM_NOV_2024\",\n          \"Detalle\": \"En el campo del cuerpo, debe imprimir la palabra NOM_MES LAS 3 PRIMERA LETRAS DE CADA MES_AÑO, Ejemplo NOM_ENE_2024, por cada registro\"\n        },\n        {\n          \"Nombre Campo\": \"ID SUBSIDIARIA\", \n          \"Tipo\": \"Texto\",\n          \"Referencia atributo\": \"Personalizado\",\n          \"Largo (txt o csv)\": \"\",\n          \"Atributo personalizado\": \"ID SUBSIDIARIA\",\n          \"Formato requerido\": \"\",\n          \"Ejemplo\": \"4\",\n          \"Detalle\": \"El campo en el cuerpo debe imprimir en cada registo lo que contegan el atributo personalizado creado en empresa llamado ID SUBSIDIARIA\"\n        },\n        {\n          \"Nombre Campo\": \"FECHA\", \n          \"Tipo\": \"Fecha\",\n          \"Referencia atributo\": \"Por defecto\",\n          \"Largo (txt o csv)\": \"\",\n          \"Atributo personalizado\": \"\",\n          \"Formato requerido\": \"\",\n          \"Ejemplo\": \"1/31/2024\",\n          \"Detalle\": \"El campo en el cuerpo debe imprimir siempre la ultima fecha de cada mes en formato DIA/MES/AÑO Ejemplo: 31/01/2024, por cada registro\"\n        },\n        {\n          \"Nombre Campo\": \"Período contable\", \n          \"Tipo\": \"Fecha\",\n          \"Referencia atributo\": \"Por defecto\",\n          \"Largo (txt o csv)\": \"\",\n          \"Atributo personalizado\": \"\",\n          \"Formato requerido\": \"\",\n          \"Ejemplo\": \"ene-24\",\n          \"Detalle\": \"El campo en el cuerpo debe imprimir siempre el mes en minusculas y solo las 3 primeras letras mas un guion (-) y los ultimos dos digitos del año Ejemplo ene-24, por cada registro\"\n        },\n        {\n          \"Nombre Campo\": \"NOTA\", \n          \"Tipo\": \"Fecha\",\n          \"Referencia atributo\": \"Por defecto\",\n          \"Largo (txt o csv)\": \"\",\n          \"Atributo personalizado\": \"\",\n          \"Formato requerido\": \"\",\n          \"Ejemplo\": \"NOM_NOV_2024_AUXILIO DE TRANSPORTE\",\n          \"Detalle\": \"El campo en el cuerpo debe imprimir lo de la casilla A mas el guion al piso mas el nombre del item en mayuscula, ejemplo: NOM_NOV_2024_AUXILIO DE TRANSPORTE\"\n        },\n        {\n          \"Nombre Campo\": \"ID MONEDA\", \n          \"Tipo\": \"Texto\",\n          \"Referencia atributo\": \"Por defecto\",\n          \"Largo (txt o csv)\": \"\",\n          \"Atributo personalizado\": \"\",\n          \"Formato requerido\": \"\",\n          \"Ejemplo\": \"2\",\n          \"Detalle\": \"El campo en el cuerpo debe imprimir siempre 2, por cada registro\"\n        },\n        {\n          \"Nombre Campo\": \"MONEDA\", \n          \"Tipo\": \"Texto\",\n          \"Referencia atributo\": \"Por defecto\",\n          \"Largo (txt o csv)\": \"\",\n          \"Atributo personalizado\": \"\",\n          \"Formato requerido\": \"\",\n          \"Ejemplo\": \"COP\",\n          \"Detalle\": \"El campo en el cuerpo debe imprimir siempre la palabra: COP en mayuscula, por cada registro\"\n        },\n        {\n          \"Nombre Campo\": \"ID CUENTA\", \n          \"Tipo\": \"Texto\",\n          \"Referencia atributo\": \"Personalizado\",\n          \"Largo (txt o csv)\": \"\",\n          \"Atributo personalizado\": \"ID CUENTA\",\n          \"Formato requerido\": \"\",\n          \"Ejemplo\": \"3664\",\n          \"Detalle\": \"En el campo del cuerpo, debe imprimir el numero de ID de cuenta, por cada registro, para esto se creo el atributo personalizado en cuentas contables \"\n        },\n        {\n          \"Nombre Campo\": \"Cuenta\", \n          \"Tipo\": \"Numero\",\n          \"Referencia atributo\": \"Por defecto\",\n          \"Largo (txt o csv)\": \"\",\n          \"Atributo personalizado\": \"\",\n          \"Formato requerido\": \"\",\n          \"Ejemplo\": \"510506001\",\n          \"Detalle\": \"En el campo del cuerpo, debe imprimir la cuenta contable, teniendo en cuenta que la empresa maneja 2 tipos de planes de cuenta contables, los cuales se crearon como atributo personalizado en la sección de cuenta contable (Administrativo,Ventas). Adicional se creó un atributo personalizado en la sección de trabajos, para que el cliente le asigne el plan contable a cada empleado.\"\n        },\n        {\n          \"Nombre Campo\": \"NOMBRE CUENTA\", \n          \"Tipo\": \"Texto\",\n          \"Referencia atributo\": \"Personalizado\",\n          \"Largo (txt o csv)\": \"\",\n          \"Atributo personalizado\": \"Nombre Cuenta\",\n          \"Formato requerido\": \"\",\n          \"Ejemplo\": \"SALARIOS POR PAGAR\",\n          \"Detalle\": \"En el campo del cuerpo, debe imprimir el Nombre de la Cuenta Contable segun corresponda, para este se creo un atributo personalizado en cuentas contables llamado: \"\n        },\n        {\n          \"Nombre Campo\": \"IMPORTE (DÉBITO)\", \n          \"Tipo\": \"Numero\",\n          \"Referencia atributo\": \"Por defecto\",\n          \"Largo (txt o csv)\": \"\",\n          \"Atributo personalizado\": \"\",\n          \"Formato requerido\": \"\",\n          \"Ejemplo\": \"25000\",\n          \"Detalle\": \"El campo en el cuerpo debe imprimir el movimiento débito sin ningún carácter especial, los campos que no tengan información deben venir en vacio\"\n        },\n        {\n          \"Nombre Campo\": \"IMPORTE (CRÉDITO)\", \n          \"Tipo\": \"Numero\",\n          \"Referencia atributo\": \"Por defecto\",\n          \"Largo (txt o csv)\": \"\",\n          \"Atributo personalizado\": \"\",\n          \"Formato requerido\": \"\",\n          \"Ejemplo\": \"25000\",\n          \"Detalle\": \"El campo en el cuerpo debe imprimir el movimiento crédito sin ningún carácter especial, los campos que no tengan información deben venir en vacio\"\n        },\n        {\n          \"Nombre Campo\": \"NOTA DE LINEA\", \n          \"Tipo\": \"Fecha\",\n          \"Referencia atributo\": \"Por defecto\",\n          \"Largo (txt o csv)\": \"\",\n          \"Atributo personalizado\": \"\",\n          \"Formato requerido\": \"\",\n          \"Ejemplo\": \"NOM_NOV_2024_AUXILIO DE TRANSPORTE\",\n          \"Detalle\": \"El campo en el cuerpo debe imprimir lo de la casilla A mas el guion al piso mas el nombre del item en mayuscula, ejemplo: NOM_NOV_2024_AUXILIO DE TRANSPORTE….. Lo mismo de la E\"\n        },\n        {\n          \"Nombre Campo\": \"ID CLASE\", \n          \"Tipo\": \"Texto\",\n          \"Referencia atributo\": \"Por defecto\",\n          \"Largo (txt o csv)\": \"\",\n          \"Atributo personalizado\": \"\",\n          \"Formato requerido\": \"\",\n          \"Ejemplo\": \"\",\n          \"Detalle\": \"Campo debe imprimir en vacio \"\n        },\n        {\n          \"Nombre Campo\": \"CLASE\", \n          \"Tipo\": \"Texto\",\n          \"Referencia atributo\": \"Por defecto\",\n          \"Largo (txt o csv)\": \"\",\n          \"Atributo personalizado\": \"\",\n          \"Formato requerido\": \"\",\n          \"Ejemplo\": \"\",\n          \"Detalle\": \"Campo debe imprimir en vacio \"\n        },\n        {\n          \"Nombre Campo\": \"ID CATEGORIAS PRODUCTOS\", \n          \"Tipo\": \"Texto\",\n          \"Referencia atributo\": \"Por defecto\",\n          \"Largo (txt o csv)\": \"\",\n          \"Atributo personalizado\": \"\",\n          \"Formato requerido\": \"\",\n          \"Ejemplo\": \"\",\n          \"Detalle\": \"Campo debe imprimir en vacio \"\n        },\n        {\n          \"Nombre Campo\": \"CATEGORIAS PRODUCTOS\", \n          \"Tipo\": \"Texto\",\n          \"Referencia atributo\": \"Por defecto\",\n          \"Largo (txt o csv)\": \"\",\n          \"Atributo personalizado\": \"\",\n          \"Formato requerido\": \"\",\n          \"Ejemplo\": \"\",\n          \"Detalle\": \"Campo debe imprimir en vacio \"\n        },\n        {\n          \"Nombre Campo\": \"ID DEPARTAMENTO\", \n          \"Tipo\": \"Texto\",\n          \"Referencia atributo\": \"Personalizado\",\n          \"Largo (txt o csv)\": \"\",\n          \"Atributo personalizado\": \"ID Centro de Costo\",\n          \"Formato requerido\": \"\",\n          \"Ejemplo\": \"1\",\n          \"Detalle\": \"Debe imprimir el Id del centro de costo, para esto se creo un atributo personalizado en Seccion de Centro de costo llamado Id Centro de Costo, para que dependiendo el centro de costo que tenga el colaborador me traiga el Id Centro de Costo, adicional otro en cuentas contables llamado Centro Costo, para que el cliente indique si desea que salga centro de costo o no\"\n        },\n        {\n          \"Nombre Campo\": \"DEPARTAMENTO\", \n          \"Tipo\": \"Texto\",\n          \"Referencia atributo\": \"Personalizado\",\n          \"Largo (txt o csv)\": \"\",\n          \"Atributo personalizado\": \"Nombre Centro de Costo\",\n          \"Formato requerido\": \"\",\n          \"Ejemplo\": \"2001 BODEGA - RECURSOS FISICOS\",\n          \"Detalle\": \"Debe imprimir el Nombre Centro de Costo, para esto se creo un atributo personalizado en Seccion de Centro de costo llamado Nombre Centro de Costo, para que dependiendo el centro de costo que tenga el colaborador me traiga el Id Centro de Costo, adicional otro en cuentas contables llamado Centro Costo, para que el cliente indique si desea que salga centro de costo o no \"\n        },\n        {\n          \"Nombre Campo\": \"ID UBICACIÓN\", \n          \"Tipo\": \"Texto\",\n          \"Referencia atributo\": \"Por defecto\",\n          \"Largo (txt o csv)\": \"\",\n          \"Atributo personalizado\": \"\",\n          \"Formato requerido\": \"\",\n          \"Ejemplo\": \"142\",\n          \"Detalle\": \"En el campo del cuerpo imprimir siempre 142 en cada registro\"\n        },\n        {\n          \"Nombre Campo\": \"UBICACIÓN\", \n          \"Tipo\": \"Texto\",\n          \"Referencia atributo\": \"Por defecto\",\n          \"Largo (txt o csv)\": \"\",\n          \"Atributo personalizado\": \"\",\n          \"Formato requerido\": \"\",\n          \"Ejemplo\": \"Oficina Bogotá\",\n          \"Detalle\": \"En el campo del cuerpo imprimir siempre Oficina Bogotá en cada registro\"\n        },\n        {\n          \"Nombre Campo\": \"ID TERCERO\", \n          \"Tipo\": \"Texto\",\n          \"Referencia atributo\": \"Personalizado\",\n          \"Largo (txt o csv)\": \"\",\n          \"Atributo personalizado\": \"\",\n          \"Formato requerido\": \"\",\n          \"Ejemplo\": \"2522\",\n          \"Detalle\": \"Revisar archivo de Word donde se la la logica por Tablas\"\n        }\n      ]\n    }\n}"
        },
        {
          "role": "user",
          "content": data.to_s
        }
      ],
      "temperature": 1,
      "max_tokens": 4095,
      "top_p": 1,
      "frequency_penalty": 0,
      "presence_penalty": 0
    }


    response = RestClient.post(openai_url, payload.to_json, {content_type: "application/json", :Authorization => "Bearer #{@api_key}"})
    content = JSON.parse(response.body)&.dig("choices",0, "message", "content")
    content = content.gsub(/^```json\s*|```$/, '')
    JSON.parse(content)
  end

  private

  def get_template(data)
    FileManagerHandler.get_template(data)
  end
end


# Parece que el assistant es más caro, mejor llamar al chat completion para que retorne la funcion con la data para elegir el template, y luego que complete el template. fin