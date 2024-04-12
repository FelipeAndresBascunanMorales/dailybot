# EXAMPLE 1
#agecofer.rb


# frozen_string_literal: true

#
#Centralizacion Personalizada Agecofer
class Exportador::Contabilidad::Peru::Personalizadas::Agecofer < Exportador::Contabilidad::Peru::CentralizacionContable
  def initialize
    super()
    @extension = 'xlsx'
  end

  CABECERA = ['Libro: Centralización Contable'].freeze
  TITULOS = ['NUMERO DE DOCUMENTO', 'NOMBRE COMPLETO', 'CUENTA CONTABLE', 'VALOR DEBE', 'VALOR HABER', 'CENTRO COSTOS', 'DESCRIPCIÓN CONCEPTO'].freeze

  NO_CONTABILIZAR_INFORMATIVOS = [
    'provision_vacaciones_deber',
    'provision_vacaciones_haber',
    'provision_cts_deber',
    'provision_cts_haber',
    'provision_gratificacion_deber',
    'provision_gratificacion_haber',
    'provision_bonificacion_extraordinaria_gratificacion_deber',
    'provision_bonificacion_extraordinaria_gratificacion_haber',
    'provision_bonificacion_extraordinaria_mensual_contabilizar_deber',
    'provision_bonificacion_extraordinaria_mensual_contabilizar_haber',
    'provision_gratificacion_ajuste_mes_deber',
    'provision_gratificacion_ajuste_mes_haber',
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    obj_contabilidad = descartar_informativos(obj_contabilidad)
    grouped = obj_contabilidad.group_by{|obj| obj.cuenta_custom_attrs['Tipo de asiento'] || "Otros"}
    grouped.map do |k, v|
      libro = generate_datos(empresa, variable, v)
      ["file_#{k}", Exportador::Contabilidad::AccountingFile.new(contents: libro, name_formatter: -> (name) { "#{name}-#{k}" })]
    end.to_h
  end

  def generate_datos(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    fecha_generacion = Time.zone.now.strftime("%d/%m/%Y a las %I:%M%p")

    Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA, 0)
    cabecera = ['Empresa: ' + empresa.nombre + ' (' + empresa.rut.humanize + ')']
    Exportador::BaseXlsx.crear_encabezado(sheet, cabecera, 1)
    cabecera = ['Periodo: ' + I18n.l(variable.end_date, format: "%B %Y").capitalize]
    Exportador::BaseXlsx.crear_encabezado(sheet, cabecera, 2)
    cabecera = ['Fecha Generación: ' + fecha_generacion.to_s]
    Exportador::BaseXlsx.crear_encabezado(sheet, cabecera, 3)
    Exportador::BaseXlsx.crear_encabezado(sheet, TITULOS, 5)

    agrupador = obj_contabilidad.group_by do |l|
      {
        rut: search_numero_documento(l),
        nombre_completo: get_nombre_completo(l),
        cuenta_contable: search_account_afp(l),
        centro_costo: search_cc(l, 'Cenco'),
        deber_o_haber: l.deber_o_haber,
        glosa: search_glosa_afp(l),
      }
    end

    excel_data = agrupador.lazy.map do |k, v|
      [
        k[:rut],
        k[:nombre_completo],
        k[:cuenta_contable],
        k[:deber_o_haber] == "D" ? v.sum(&:monto) : 0,
        k[:deber_o_haber] == "C" ? v.sum(&:monto) : 0,
        k[:centro_costo],
        k[:glosa],
      ]
    end
    Exportador::BaseXlsx.escribir_celdas sheet, excel_data, offset: 6
    Exportador::BaseXlsx.autofit sheet, [TITULOS]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  private
    def get_nombre_completo l
      l.employee.nombre_completo if l.cuenta_custom_attrs["Agrupador"].to_s.casecmp("DNI").zero?
    end

    def search_account_afp l
      return get_cuenta_contable(l) unless l.cuenta_custom_attrs["AFP"].to_s.casecmp('si').zero?
      afp_method(l)&.numero
    end

    def get_cuenta_contable l
      plan_contable = l.centro_costo
      l.cuenta_custom_attrs[plan_contable].presence || l.cuenta_contable
    end

    def descartar_informativos(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_INFORMATIVOS.include?(l.nombre_cuenta)
      end
    end
end

# EXAMPLE 2
#araya_peru.rb


# frozen_string_literal: true

# Archivo de Centralizacion Personalizada cliente Araya Perú
class Exportador::Contabilidad::Peru::Personalizadas::ArayaPeru < Exportador::Contabilidad::Peru::CentralizacionContable
  def initialize
    super()
    @extension = 'xlsx'
  end

  HEADER = [
    "Campo",
    "Sub Diario",
    "Número de Comprobante",
    "Fecha de Comprobante",
    "Código de Moneda",
    "Glosa Principal",
    "Tipo de Cambio",
    "Tipo de Conversión",
    "Flag de Conversión de Moneda",
    "Fecha Tipo de Cambio",
    "Cuenta Contable",
    "Código de Anexo",
    "Código de Centro de Costo",
    "Debe / Haber",
    "Importe Original",
    "Importe en Dólares",
    "Importe en Soles",
    "Tipo de Documento",
    "Número de Documento",
    "Fecha de Documento",
    "Fecha de Vencimiento",
    "Código de Area",
    "Glosa Detalle",
    "Código de Anexo Auxiliar",
    "Medio de Pago",
    "Tipo de Documento de Referencia",
    "Número de Documento Referencia",
    "Fecha Documento Referencia",
    "Nro Máq. Registradora Tipo Doc. Ref.",
    "Base Imponible Documento Referencia",
    "IGV Documento Provisión",
    "Tipo Referencia en estado MQ",
    "Número Serie Caja Registradora",
    "Fecha de Operación",
    "Tipo de Tasa",
    "Tasa Detracción/Percepción",
    "Importe Base Detracción/Percepción Dólares",
    "Importe Base Detracción/Percepción Soles",
    "Tipo Cambio para 'F'",
    "Importe de IGV sin derecho crédito fiscal",
  ].freeze

  NO_CONTABILIZAR_INFORMATIVOS = ["buk_vida_ley"].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    mes = date.strftime("%m")
    fecha = date.strftime("%d/%m/%Y")
    anio = date.strftime("%Y")
    obj_contabilidad = descartar_informativos(obj_contabilidad)

    libros = {}
    obj_contabilidad_grupo = obj_contabilidad.group_by{|l| l.cuenta_custom_attrs&.dig('Tipo de asiento') || "Sin clasificar"}

    obj_contabilidad_grupo.each do |k, obj|
      concepto = k.upcase
      libro = excel_data(obj, empresa, variable, mes, fecha, anio, concepto)
      libros["Libro_#{k}".to_sym] = Exportador::Contabilidad::AccountingFile.new(contents: libro, name_formatter: -> (name) {"#{name} #{concepto}"})
    end
    libros
  end

  def excel_data(obj_contabilidad, empresa, variable, mes, fecha, anio, concepto)
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    Exportador::BaseXlsx.crear_encabezado(sheet, HEADER, 0)

    tipo_cambio = kpi_dolar(variable.id, empresa.id) || 1

    agrupador = obj_contabilidad.group_by do |l|
      {
        cuenta_contable: l.cuenta_contable,
        cod_anexo: get_cod_anexo(l),
        centro_costo: get_cenco(l),
        deber_o_haber: l.deber_o_haber,
        columna_dh: l.cuenta_custom_attrs&.dig("Debe/Haber"),
        codigo_asiento: concepto == "SIN CLASIFICAR" ? "0000" : l.cuenta_custom_attrs&.dig("Código Asiento"),
      }
    end
    data = agrupador.map do |k, v|
      [
        nil,
        "35",
        "#{mes}#{k[:codigo_asiento]}",
        fecha,
        "MN",
        "#{concepto} #{mes}-#{anio}",
        tipo_cambio,
        "V",
        "S",
        nil,
        k[:cuenta_contable],
        k[:cod_anexo].to_s,
        k[:centro_costo],
        k[:columna_dh],
        v.sum(&:monto),
        (v.sum(&:monto) / tipo_cambio),
        v.sum(&:monto),
        "PL",
        "#{mes}-#{anio}",
        fecha,
        fecha,
        nil,
        "#{concepto} #{mes}-#{anio}",
      ]
    end
    Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 1, number_format: "###0.00"
    Exportador::BaseXlsx.autofit sheet, [HEADER]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  private
    def get_cod_anexo obj
      return unless obj.cuenta_custom_attrs&.dig("Mostra Código Anexo").to_s.parameterize == "si"
      if obj.tipo_doc.present?
        obj.tipo_doc
      else
        obj.cuenta_custom_attrs&.dig("AFP").to_s.parameterize == "si" ? obj.cuenta_custom_attrs&.dig(obj.afp) : obj.numero_documento.to_s
      end
    end

    def get_cenco obj
      search_cenco(obj) unless obj.cuenta_custom_attrs&.dig("Agrupador") == "TOTAL"
    end

    def descartar_informativos(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_INFORMATIVOS.include?(l.item_code)
      end
    end
end

# EXAMPLE 3
#bbk_group_peru_s_a_c.rb


# rubocop:disable Buk/FileNameClass
#Clase para la centralizacion personaliza cliente BBK GROUP PERU SAC
class Exportador::Contabilidad::Peru::Personalizadas::BbkGroupPeruSAC < Exportador::Contabilidad
  def initialize
    super()
    @extension = 'xlsx'
  end
  def generate_doc(_empresa, variable, obj_contabilidad)
  # book
    return unless obj_contabilidad.present?
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    fecha = variable.end_date.strftime('%d/%m/%Y')
    fecha_doc = Time.zone.now.strftime("%m/%Y")
    mes = variable.end_date.strftime("%m")
    fecha_generacion = Time.zone.now.strftime("%d/%m/%Y")
    fecha_glosa = variable.end_date.strftime('%m-%Y')
    sheet = Exportador::BaseXlsx.crear_hoja book, "contabilidad"
    titulos = [
      'Campo',
      'Sub Diario',
      'Número de Comprobante',
      'Fecha de Comprobante',
      'Código de Moneda',
      'Glosa Principal',
      'Tipo de Cambio',
      'Tipo de Conversión',
      'Flag de Conversión de Moneda',
      'Fecha Tipo de Cambio',
      'Cuenta Contable',
      'Código de Anexo',
      'Código de Centro de Costo',
      'Debe / Haber',
      'Importe Original',
      'Importe en Dólares',
      'Importe en Soles',
      'Tipo de Documento',
      'Número de Documento',
      'Fecha de Documento',
      'Fecha de Vencimiento',
      'Código de Area',
      'Glosa Detalle',
      'Código de Anexo Auxiliar',
      'Medio de Pago',
      'Tipo de Documento de Referencia',
      'Número de Documento Referencia',
      'Fecha Documento Referencia',
      'Nro Máq. Registradora Tipo Doc. Ref.',
      'Base Imponible Documento Referencia',
      'IGV Documento Provisión',
      'Tipo Referencia en estado MQ',
      'Número Serie Caja Registradora',
      'Fecha de Operación',
      'Tipo de Tasa',
      'Tasa Detracción/Percepción',
      'Importe Base Detracción/Percepción Dólares',
      'Importe Base Detracción/Percepción Soles',
      "Tipo Cambio para 'F'",
      'Importe de IGV sin derecho crédito fiscal',
    ]
    Exportador::BaseXlsx.escribir_celdas sheet, [titulos], offset: 0, number_format: '#,##0'
    excel_data = obj_contabilidad.map  do |o|
      [
        nil,
        "35", # Sub Diario'
        "#{mes}0001", # Número de Comprobante'
        fecha, # Fecha de Comprobante'
        "MN", # Código de Moneda'
        "#{o.glosa} #{fecha_glosa}".first(40), # Glosa Principal'
        nil, # Tipo de Cambio'
        'V', # Tipo de Conversión'
        'S', # Flag de Conversión de Moneda'
        nil, # Fecha Tipo de Cambio'
        o.cuenta_contable, # Cuenta Contable'
        muestra_dni(o), # Código de Anexo'
        o.centro_costo, # Código de Centro de Costo'
        o.deber_o_haber == 'C' ? 'H' : 'D', # Debe / Haber'
        o.monto.to_s, # Importe Original'
        nil, # Importe en Dólares'
        nil, # Importe en Soles'
        'PL', # Tipo de Documento'
        fecha_doc, # Número de Documento'
        fecha_generacion, # Fecha de Documento'
        fecha, # Fecha de Vencimiento'
        nil, # Código de Area'
        o.glosa&.first(30), # Glosa Detalle'
        nil, # Código de Anexo Auxiliar'
        nil, # Medio de Pago'
        nil, # Tipo de Documento de Referencia'
        nil, # Número de Documento Referencia'
        nil, # Fecha Documento Referencia'
        nil, # Nro Máq. Registradora Tipo Doc. Ref.'
        nil, # Base Imponible Documento Referencia'
        nil, # IGV Documento Provisión'
        nil, # Tipo Referencia en estado MQ'
        nil, # Número Serie Caja Registradora'
        nil, # Fecha de Operación'
        nil, # Tipo de Tasa'
        nil, # Tasa Detracción/Percepción'
        nil, # Importe Base Detracción/Percepción Dólare'
        nil, # Importe Base Detracción/Percepción Soles'
        nil, # Tipo Cambio para F'
        nil, # Importe de IGV sin derecho crédito fiscal'
      ]
    end
    Exportador::BaseXlsx.escribir_celdas sheet, excel_data, offset: 1, number_format: '#,##0'
    Exportador::BaseXlsx.autofit sheet, [titulos]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def muestra_dni l
    case l.cuenta_custom_attrs&.dig("RUC")
    when 'AFP'
      l.afp == "Profuturo AFP" ? "AFP-PRO" : l.ruc_afp
    when 'FUNCIONARIO'
      l.numero_documento&.dash&.tr("-", "")
    end
  end
end
# rubocop:enable Buk/FileNameClass

# EXAMPLE 4
#grupo_andina.rb


# frozen_string_literal: true

# Clase para centralizacion: Grupo Andina
class Exportador::Contabilidad::Peru::Personalizadas::GrupoAndina < Exportador::Contabilidad::Peru::CentralizacionContable
  def initialize
    super()
    @extension = 'xlsx'
  end

  FIRST_HEADER = [
    'JdtNum',
    'ReferenceDate',
    'Memo',
    'Reference',
    'Reference2',
    'TransactionCode',
    'ProjectCode',
    'TaxDate',
    'Indicator',
    'UseAutoStorno',
    'StornoDate',
    'VatDate',
  ].freeze

  SECOND_HEADER = [
    'Num registro',
    'fecha contable',
    'Memo',
    'Ref1',
    'Ref2',
    'TransCode',
    'Project',
    'Fecha doc',
    'Indicator',
    'AutoStorno',
    'StornoDate',
    'Fecha venc',
  ].freeze

  FIRST_HEADER_DETAIL = [
    'ParentKey',
    'LineNum',
    'Cuenta',
    'AccountCode',
    'FCCurrency',
    'FCDebit',
    'FCCredit',
    'Debit',
    'Credit',
    'ShortName',
    'LineMemo',
    'Reference1',
    'CostingCode',
    'CostingCode2',
    'CostingCode3',
  ].freeze

  SECOND_HEADER_DETAIL = [
    'Numero registro',
    'LineNum',
    'Cuenta',
    'Cuenta',
    'Moneda',
    'DebitoDolares',
    'CreditoDolares',
    'Debito',
    'Credito',
    'ShortName/ cta socio negocio',
    'Glosa',
    'Referencia 1',
    'AREA',
    'CENTRO COSTO',
    'LINEA NEGOCIO',
  ].freeze

  NO_CONTABILIZAR_INFORMATIVOS = [
    'aporte_a_eps_por_vacaciones_deber',
    'aporte_a_eps_por_vacaciones_haber',
    'aporte_a_essalud_por_vacaciones_deber',
    'aporte_a_essalud_por_vacaciones_haber',
    'apv',
    'buk_finiquito_aporte_afp',
    'buk_finiquito_aporte_onp',
    'buk_finiquito_bonificacion_extraordinaria_gratificacion',
    'buk_finiquito_comision_afp',
    'buk_finiquito_cts_trunca',
    'buk_finiquito_devolucion_quinta_categoria',
    'buk_finiquito_formacion_constitucion_empresa',
    'buk_finiquito_gratificacion_trunca',
    'buk_finiquito_incentivo_cese',
    'buk_finiquito_indemnizacion_despido',
    'buk_finiquito_indemnizacion_vacaciones_vencidas',
    'buk_finiquito_neto_liquidacion',
    'buk_finiquito_otros_descuentos_peru',
    'buk_finiquito_seguro_afp',
    'buk_finiquito_suma_graciosa',
    'buk_finiquito_vacaciones',
    'buk_finiquito_vacaciones_eps_deber',
    'buk_finiquito_vacaciones_eps_haber',
    'buk_finiquito_vacaciones_essalud_deber',
    'buk_finiquito_vacaciones_essalud_haber',
    'buk_sctr_pension_deber',
    'buk_sctr_pension_haber',
    'buk_sctr_salud_deber',
    'buk_sctr_salud_haber',
    'buk_subsidio_incapacidad_no_computable_para_cts',
    'buk_subsidio_maternidad',
    'buk_vida_ley_deber',
    'buk_vida_ley_haber',
    'provision_bonificacion_extraordinaria_gratificacion_deber',
    'provision_bonificacion_extraordinaria_gratificacion_haber',
    'provision_cts_deber',
    'provision_cts_haber',
    'provision_gratificacion_deber',
    'provision_gratificacion_haber',
    'provision_vacaciones_deber',
    'provision_vacaciones_haber',
  ].freeze

  def generate_doc empresa, variable, obj_contabilidad
    return unless obj_contabilidad.present?

    obj_contabilidad = descartar_informativos(obj_contabilidad)
    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    fecha = I18n.l(date, format: '%Y%m%d')
    mes_anio = I18n.l(date, format: '%B %Y')
    fecha_mmyyyy = I18n.l(date, format: '%m/%Y')

    obj_contabilidad_agrupado = obj_contabilidad.group_by{|l| l.cuenta_custom_attrs["Tipo de Asiento"] || "Sin asiento"}
    libro = {}

    libro = obj_contabilidad_agrupado.map do |asiento, obj_asiento|
      [asiento.to_sym, Exportador::Contabilidad::AccountingFile.new(contents: excel_header(obj_asiento, empresa, fecha, asiento, mes_anio), name_formatter: -> (name) { "#{name} #{asiento}-cabecera" })]
    end.to_h

    obj_contabilidad_agrupado.each do |asiento, obj_asiento|
      libro["#{asiento}-detalle".to_sym] = Exportador::Contabilidad::AccountingFile.new(contents: excel_detail(obj_asiento, empresa, fecha_mmyyyy), name_formatter: -> (name) { "#{name}-#{asiento}-detalle" })
    end

    libro
  end

  def excel_header obj_contabilidad, empresa, fecha, asiento, mes_anio
    return unless obj_contabilidad.present?

    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    Exportador::BaseXlsx.crear_encabezado(sheet, FIRST_HEADER, 0)
    Exportador::BaseXlsx.crear_encabezado(sheet, SECOND_HEADER, 1)
    titulo = get_titulo(asiento, mes_anio)

    data =
      [
        '1',
        fecha,
        titulo,
        nil,
        nil,
        nil,
        nil,
        fecha,
        nil,
        nil,
        nil,
        fecha,
      ]

    Exportador::BaseXlsx.escribir_celdas sheet, [data], offset: 2
    Exportador::BaseXlsx.autofit sheet, [FIRST_HEADER]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def excel_detail obj_contabilidad, empresa, fecha_mmyyyy
    return unless obj_contabilidad.present?

    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    Exportador::BaseXlsx.crear_encabezado(sheet, FIRST_HEADER_DETAIL, 0)
    Exportador::BaseXlsx.crear_encabezado(sheet, SECOND_HEADER_DETAIL, 1)

    group = get_data_agrupada(obj_contabilidad, fecha_mmyyyy)

    data = group.map.with_index do |(k, v), index|
      [
        '1',
        index.to_s,
        k[:account],
        k[:account_code],
        "USD",
        "0",
        "0",
        k[:deber_o_haber] == "D" ? v.sum(&:monto) : 0,
        k[:deber_o_haber] == "C" ? v.sum(&:monto) : 0,
        k[:dni],
        k[:glosa],
        k[:employee_name],
        k[:centro_costo],
      ]
    end
    Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 2, number_format: "###0.00"
    Exportador::BaseXlsx.autofit sheet, [FIRST_HEADER_DETAIL]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def generate_data(_empresa, variable, obj_contabilidad, **_args)
    return [] unless obj_contabilidad.present?

    obj_contabilidad = descartar_informativos(obj_contabilidad)

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    fecha = I18n.l(date, format: '%Y%m%d')
    mes_anio = I18n.l(date, format: '%B %Y')
    fecha_mmyyyy = I18n.l(date, format: '%m/%Y')
    data = []

    obj_contabilidad.group_by{|l| l.cuenta_custom_attrs["Tipo de Asiento"] || "Sin asiento"}.each do |k, obj|
      data_agrupada = get_data_agrupada(obj, fecha_mmyyyy)
      titulo = get_titulo(k, mes_anio)

      data << k
      data << data_cabecera_api(fecha, titulo)
      data << data_api(data_agrupada)
    end
    data
  end


  private
    def get_data_agrupada obj, fecha_mmyyyy
      obj.group_by do |l|
        {
          account: get_account(l),
          account_code: get_cuenta_by_segmento(l),
          dni: get_rut(l),
          glosa: get_account_name(l, fecha_mmyyyy),
          employee_name: "#{l.first_name.split(" ")[0]} #{l.last_name}".upcase,
          centro_costo: search_cenco(l),
          deber_o_haber: l.deber_o_haber,
        }
      end
    end

    def data_cabecera_api fecha, titulo
      {
        num_registro: '1',
        fecha_contable: fecha,
        memo: titulo,
        fecha_doc: fecha,
        fecha_venc: fecha,
      }
    end

    def data_api group
      group.map.with_index do |(k, v), index|
        [
          numero_registro: '1',
          linenum: index.to_s,
          cuenta: k[:account],
          account_code: k[:account_code],
          moneda: "USD",
          debitodolares: "0",
          creditodolares: "0",
          debito: k[:deber_o_haber] == "D" ? v.sum(&:monto) : 0,
          credito: k[:deber_o_haber] == "C" ? v.sum(&:monto) : 0,
          short_name: k[:dni],
          glosa: k[:glosa],
          referencia_1: k[:employee_name],
          area: k[:centro_costo],
        ]
      end
    end

    def get_titulo asiento, mes_anio
      "#{asiento} #{mes_anio}".upcase
    end

    def get_account_name obj, fecha_mmyyyy
      req_fecha, nomb_cuenta, period_vac = attrs_afp(obj)

      return "#{nomb_cuenta.upcase} #{fecha_mmyyyy} #{obj.first_name.split(" ")[0].upcase} #{obj.last_name.upcase}" if req_fecha.to_s.casecmp("si").zero?
      obj.employee_custom_attrs["Periodo de vacaciones - contabilidad"] if period_vac.to_s.casecmp("si").zero?
    end

    def get_cuenta_by_segmento obj
      plan_contable = obj.employee_custom_attrs["Segmento contable"]
      return obj.cuenta_contable unless plan_contable.present?
      obj.cuenta_custom_attrs["AFP"].to_s.casecmp('si').zero? ? afp_method(obj)&.custom_attrs&.dig(plan_contable) : obj.cuenta_custom_attrs[plan_contable]
    end

    def get_account obj
      segmento_cont = obj.cuenta_custom_attrs["AFP"].to_s.casecmp('si').zero? ? afp_method(obj)&.custom_attrs&.dig('Usar segmento contable') : obj.cuenta_custom_attrs["Usar segmento contable"]
      segmento_cont.to_s.casecmp("si").zero? ? "#{search_account(obj)}#{obj.employee_custom_attrs["Segmento contable"].to_s[0..1]}" : "#{search_account(obj)}00"
    end

    def get_rut obj
      "#{obj.cuenta_custom_attrs["Short Name"]}#{obj.numero_documento}" if obj.cuenta_custom_attrs["Short Name"].present?
    end

    def attrs_afp obj
      return [afp_method(obj)&.custom_attrs&.dig('Requiere fecha'), afp_method(obj)&.custom_attrs&.dig('Nombre de la cuenta'), afp_method(obj)&.custom_attrs&.dig('Periodo de vacaciones')] if obj.cuenta_custom_attrs["AFP"].to_s.casecmp('si').zero?
      [obj.cuenta_custom_attrs["Requiere fecha"], obj.cuenta_custom_attrs["Nombre de la cuenta"], obj.cuenta_custom_attrs["Periodo de vacaciones"]]
    end

    def descartar_informativos(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_INFORMATIVOS.include?(l.nombre_cuenta)
      end
    end
end

# EXAMPLE 5
#keypro_peru.rb


# frozen_string_literal: true

#Exportador de comprobante para empresa KeyproPeru
class Exportador::Contabilidad::Peru::Personalizadas::KeyproPeru < Exportador::Contabilidad::Peru::CentralizacionContable
  def initialize
    super()
    @extension = 'xlsx'
  end

  HEADER = [
    'O.',
    'Vou',
    'Cuenta',
    'Descripción',
    'Débito',
    'Crédito',
    'M',
    'T/C',
    'Fecha',
    'Concepto',
    'Código',
    'Razón Social',
    'Doc',
    'Numero',
    'F.Emisión',
    'F.Vencimiento',
    'C.C.',
    'Pre.',
    'F.E.',
    'Zona',
    'Vendedor',
    'R.Doc',
    'R.Numero',
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    hashes = {}
    obj_contabilidad_custom = obj_contabilidad.group_by{|l| l.cuenta_custom_attrs["Tipo de asiento"] || "Sin Tipo de asiento"}

    obj_contabilidad_custom.each do |k, obj|
      libro = generate_centralizacion(empresa, variable, obj, k)
      hashes["Libro_#{k}".to_sym] = Exportador::Contabilidad::AccountingFile.new(contents: libro, name_formatter: -> (name) {"#{name} - #{k}"})
    end
    hashes
  end

  def generate_centralizacion(empresa, variable, obj_contabilidad, tipo)
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, "Centralización Contable"
    Exportador::BaseXlsx.crear_encabezado(sheet, HEADER, 0)
    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)

    tipo_cambio = kpi_dolar(variable.id, empresa.id, "tipo_de_cambio") || 1
    end_date = date.strftime('%d/%m/%Y')
    month_year = I18n.l(date, format: '%B-%Y').upcase
    fecha_asiento = "#{tipo}-#{month_year}"
    excel_data = []

    order_obj_contabilidad = obj_contabilidad.sort_by(&:numero_documento)

    group_by_rut = order_obj_contabilidad.group_by do |ll|
      {
        dni: ll.numero_documento&.humanize,
      }
    end

    agrupador = order_obj_contabilidad.group_by do |l|
      {
        tipo_asiento: tipo_asiento(tipo, l),
        account: account(l).to_s,
        descripcion: descripcion(l),
        deber_o_haber: l.deber_o_haber,
        dni: l.numero_documento&.humanize,
      }
    end

    group_by_rut.each do |key, _value| # rubocop:todo Style/HashEachMethods
      excel_data << [key[:dni]]
      agrupador.each do |k, v|
        next if key[:dni] != k[:dni]
        excel_data << [
          "11",
          k[:tipo_asiento],
          k[:account],
          k[:descripcion],
          k[:deber_o_haber] == 'D' ? v.sum(&:monto) : "-",
          k[:deber_o_haber] == 'C' ? v.sum(&:monto) : "-",
          "S",
          tipo_cambio,
          end_date,
          fecha_asiento,
          k[:dni],
          nil,
          nil,
          nil,
          end_date,
          end_date,
        ]
      end
    end
    Exportador::BaseXlsx.escribir_celdas sheet, excel_data, offset: 1
    Exportador::BaseXlsx.autofit sheet, [HEADER]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  private
    def account l
      return afp_method(l)&.numero if l.cuenta_custom_attrs["AFP"].to_s.upcase.squish == "SI"
      l.cuenta_custom_attrs["Cuenta #{l.employee_custom_attrs["Tipo de Colaborador"]}"].presence || l.cuenta_contable
    end

    def tipo_asiento tipo, l
      case tipo
      when "Provisión de Planilla"
        l.employee_custom_attrs['Vou Planilla']
      when "Liquidación"
        l.employee_custom_attrs['Vou Liquidaciones']
      when "Beneficios"
        l.employee_custom_attrs['Vou Provisiones']
      end
    end

    def descripcion l
      l.cuenta_custom_attrs["AFP"].to_s.upcase.squish == "SI" ? afp_method(l)&.custom_attrs&.dig('Descripción') : l.cuenta_custom_attrs['Descripción']
    end
end

# EXAMPLE 6
#grupo_woll.rb


# frozen_string_literal: true

#
# clase para generar centralizacion contable personalizada para grupo woll
class Exportador::Contabilidad::Peru::Personalizadas::GrupoWoll < Exportador::Contabilidad::Peru::CentralizacionContable
  def initialize
    super()
    @extension = 'xlsx'
  end

  CABECERA = [
    'cod_actividad',
    'cod_centro_costo',
    'cod_cuenta',
    'cod_tipo_anexo',
    'cod_tipo_documento',
    'cod_tipo_gasto',
    'glosa_detalle',
    'importe',
    'indica_debe_haber',
    'nro_doc_identificacion',
    'numero',
    'serie',
  ].freeze

  CABECERA_2 = [
    'ASIENTO',
    'CENTRO COSTO',
    'CLASE ASIENTO',
    'CONTRIBUYENTE',
    'CUENTA CONTABLE',
    'CREDITO LOCAL',
    'DEBITO LOCAL',
    'FECHA',
    'FUENTE',
    'PAQUETE',
    'REFERENCIA',
    'TIPO ASIENTO',
    'TIPO CONTABILIDAD',
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    tipo_empresa = empresa.custom_attrs["Tipo de Contabilidad"]
    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)

    hashes = {}
    obj_contabilidad.group_by{|l| l.cuenta_custom_attrs["Proceso"].presence || "Otros"}.each do |k, v|
      if tipo_empresa == "EXACTUS"
        libro_exactus = generate_centra_exactus(date, k, v, tipo_empresa)
        hashes["Libro_#{k}".to_sym] = Exportador::Contabilidad::AccountingFile.new(contents: libro_exactus, name_formatter: -> (name) {"#{k}-#{name}"})
      else
        libro_datasmart = generate_centra_datasmart(date, k, v, tipo_empresa)
        hashes["Libro_#{k}".to_sym] = Exportador::Contabilidad::AccountingFile.new(contents: libro_datasmart, name_formatter: -> (name) {"#{k}-#{name}"})
      end
    end
    hashes
  end
  private

    def generate_centra_datasmart(date, nombre, obj_contabilidad, tipo_empresa)
      return unless obj_contabilidad.present?

      book = Exportador::BaseXlsx.crear_libro
      book.worksheets = []
      sheet = Exportador::BaseXlsx.crear_hoja book, "#{tipo_empresa} #{nombre}"
      Exportador::BaseXlsx.autofit sheet, [CABECERA]
      Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA, 0)

      mes_anio = I18n.l(date, format: '%m %Y')

      obj_contabilidad = obj_contabilidad.group_by do |l|
        agrupador(l).merge(
          glosa: "#{l.cuenta_custom_attrs["Glosa Detalle"]} #{mes_anio.to_s.tr(" ", "")}",
          glosa2: "#{l.cuenta_custom_attrs["Glosa Secundaria"]} #{mes_anio}",
        )
      end

      data = obj_contabilidad.lazy.map do |k, v|
        [
          k[:cuenta_contable],
          "003",
          k[:dni],
          v.sum(&:monto),
          k[:lado] == 'D' ? "D" : "H",
          k[:glosa],
          "00",
          "0",
          k[:glosa2],
          k[:centro_costo],
        ]
      end

      Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 1, number_format: '#,##0'
      Exportador::BaseXlsx.cerrar_libro(book).contenido
    end

    def generate_centra_exactus(date, nombre, obj, tipo_empresa)
      return unless obj.present?

      book = Exportador::BaseXlsx.crear_libro
      book.worksheets = []
      sheet = Exportador::BaseXlsx.crear_hoja book, "#{tipo_empresa} #{nombre}"
      Exportador::BaseXlsx.autofit sheet, [CABECERA_2]
      Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA_2, 0)

      date_ddmmyyyy = I18n.l(date, format: '%d-%m-%Y')

      obj = obj.group_by do |l|
        agrupador(l)
      end

      data = obj.lazy.map do |k, v|
        [
          "PL",
          "1",
          date_ddmmyyyy,
          "PL",
          "A",
          "N",
          nil,
          nil,
          k[:dni],
          k[:centro_costos],
          k[:cuenta_contable],
          k[:lado] == 'C' ? v.sum(&:monto) : nil,
          k[:lado] == 'D' ? v.sum(&:monto) : nil,
        ]
      end
      Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 1, number_format: '#,##0'
      Exportador::BaseXlsx.cerrar_libro(book).contenido
    end

    def agrupador l
      {
        cuenta_contable: get_cuenta_by_plan_contable_dinamico(l, "job"),
        lado: l.deber_o_haber,
        centro_costos: get_cenco(l),
        dni: search_numero_documento(l),
      }
    end

    def get_cenco l
      l.centro_costo_custom_attrs["Cod Contabilidad"] if ["CENCO", "DNI"].include?(l.cuenta_custom_attrs["Agrupador"])
    end
end

# EXAMPLE 7
#mirum.rb


# frozen_string_literal: true

#
#Clase para la centralizacion personaliza cliente Mirum Peru
class Exportador::Contabilidad::Peru::Personalizadas::Mirum < Exportador::Contabilidad::Peru::CentralizacionContable
  def initialize
    super()
    @extension = 'xlsx'
  end

  CABECERA = ['Sub Diario',
              'Número de Comprobante',
              'Fecha de Comprobante',
              'Código de Moneda',
              'Glosa Principal',
              'Tipo de Cambio',
              'Tipo de Conversión',
              'Flag de Conversión de Moneda',
              'Fecha Tipo de Cambio',
              'Cuenta Contable',
              'Código de Anexo',
              'Código de Centro de Costo',
              'Debe / Haber',
              'Importe Original',
              'Importe en Dólares',
              'Importe en Soles',
              'Tipo de Documento',
              'Número de Documento',
              'Fecha de Documento',
              'Fecha de Vencimiento',
              'Código de Area',
              'Glosa Detalle',
              'Código de Anexo Auxiliar',
              'Medio de Pago',
              'Tipo de Documento de Referencia',
              'Número de Documento Referencia',
              'Fecha Documento Referencia',
              'Nro Máq. Registradora Tipo Doc. Ref.',
              'Base Imponible Documento Referencia',
              'IGV Documento Provisión',
              'Tipo Referencia en estado MQ',
              'Número Serie Caja Registradora',
              'Fecha de Operación',
              'Tipo de Tasa',
              'Tasa Detracción/Percepción',
              'Importe Base Detracción/Percepción Dólares',
              'Importe Base Detracción/Percepción Soles',
              'Tipo Cambio para F',
              'Importe de IGV sin derecho crédito fiscal',].freeze

  def generate_doc(_empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet_planilla = Exportador::BaseXlsx.crear_hoja book, "PLANILLA"
    sheet_liquidaciones = Exportador::BaseXlsx.crear_hoja book, "LIQUIDACIONES"

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    fecha = date.strftime("%d/%m/%Y")
    is_liq = false
    mes = date.strftime("%m")
    anno_mes = date.strftime("%Y-%m")
    mes_anno = date.strftime("%m-%Y")

    Exportador::BaseXlsx.crear_encabezado(sheet_planilla, CABECERA, 0)
    Exportador::BaseXlsx.crear_encabezado(sheet_liquidaciones, CABECERA, 0)

    obj_contabilidad_planilla = obj_contabilidad.reject{|obj| obj.estado == "inactivo"}
    obj_contabilidad_liquidacion = obj_contabilidad.select{|obj| obj.estado == "inactivo" && obj.cuenta_custom_attrs["Correlativo"] == "0001"}

    agrupador_planilla = obj_contabilidad_planilla.sort_by{|o| o.cuenta_custom_attrs["TIPO ASIENTO"].presence || ""}.group_by do |p|
      {
        cuenta_contable: p.cuenta_contable,
        deber_o_haber: p.deber_o_haber,
        centro_costo: search_cenco(p),
        ruc: ruc(p),
        tipo_glosa: p.cuenta_custom_attrs["TIPO ASIENTO"].presence,
        glosa_detalle: concepto(p),
        tipo_doc: p.tipo_doc,
        correlativo: p.cuenta_custom_attrs["Correlativo"],
      }
    end

    agrupador_liquidacion = obj_contabilidad_liquidacion.group_by do |p|
      {
        cuenta_contable: p.cuenta_contable,
        deber_o_haber: p.deber_o_haber,
        centro_costo: search_cenco(p),
        ruc: ruc(p),
        tipo_glosa: p.cuenta_custom_attrs["TIPO ASIENTO"].presence,
        glosa_detalle: concepto(p),
        tipo_doc: p.tipo_doc,
        correlativo: p.cuenta_custom_attrs["Correlativo"],
      }
    end

    excel_data_planilla = agrupador_planilla.map do |k, v|
      print_data(k, v, fecha, anno_mes, mes, mes_anno, is_liq = false)
    end

    excel_data_liquidacion = agrupador_liquidacion.map do |k, v|
      print_data(k, v, fecha, anno_mes, mes, mes_anno, is_liq = true)
    end

    Exportador::BaseXlsx.escribir_celdas sheet_planilla, excel_data_planilla, offset: 1, number_format: '###0.00'
    Exportador::BaseXlsx.autofit sheet_planilla, [CABECERA]
    Exportador::BaseXlsx.escribir_celdas sheet_liquidaciones, excel_data_liquidacion, offset: 1, number_format: '###0.00'
    Exportador::BaseXlsx.autofit sheet_liquidaciones, [CABECERA]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  private
      #-------------- PRINT GROUP TOTAL ----------------------------------------------------

    def print_data k, v, fecha, anno_mes, mes, mes_anno, is_liq
      [
        "35", #A
        show_correlativo(k[:correlativo], mes, is_liq), #B
        fecha, #C
        "MN", #D
        show_glosa(k[:tipo_glosa], mes_anno, is_liq), #E
        "", #F
        "M", #G
        "S", #H
        fecha, #I
        k[:cuenta_contable], #J
        k[:ruc], #K
        k[:centro_costo], #L
        k[:deber_o_haber] == "C" ? "H" : "D", #M
        v.sum(&:monto), #N
        "", #O
        v.sum(&:monto), #P
        show_tipo_doc(k[:tipo_doc], is_liq), #Q
        anno_mes, #R
        fecha, #S
        fecha, #T
        nil, #U
        k[:glosa_detalle], #V
        nil, #W
        nil, #X
        nil, #Y
        nil, #Z
        nil, #AA
        nil, #AB
        nil, #AC
        nil, #AD
        nil, #AE
        nil, #AF
        nil, #AG
        nil, #AH
        nil, #AI
        nil, #AJ
        nil, #AK
        nil, #AL
        nil, #AM
        nil, #AN
      ]
    end

    def show_tipo_doc tipo_doc, is_liq
      return tipo_doc unless is_liq
      "LS"
    end

    def show_glosa tipo_glosa, mes_anno, is_liq
      return "#{tipo_glosa} #{mes_anno}" unless is_liq
      "LIQUIDACIONES #{mes_anno}"
    end

    def show_correlativo correlativo, mes, is_liq
      return "#{mes}#{correlativo}" unless is_liq
      "#{mes}0005"
    end

    def search_cenco object
      object.centro_costo if object.cuenta_custom_attrs&.dig("DCODANE")&.upcase == "CENCO"
    end

    def ruc object
      if object.cuenta_custom_attrs&.dig("DCODANE")&.upcase == "DNI"
        object.numero_documento
      elsif object.cuenta_custom_attrs&.dig("DCODANE")&.upcase == "RUC"
        object.ruc_afp
      end
    end

    def concepto object
      object.cuenta_custom_attrs["Glosa Detalle"].presence || object.glosa
    end

end

# EXAMPLE 8
#grupo_transmeridian.rb


# frozen_string_literal: true

#
# clase para generar centralizacion contable personalizada para GrupoTransmeridian
class Exportador::Contabilidad::Peru::Personalizadas::GrupoTransmeridian < Exportador::Contabilidad::Peru::CentralizacionContable
  def initialize
    super()
    @extension = 'xlsx'
  end

  HEADER = [
    'JdtNum',
    'Memo',
    'ReferenceDate',
    'TaxDate',
    'DueDate',
    'Reference',
    'Reference2',
    'Reference3',
    'Series',
    'TransactionCode',
  ].freeze

  HEADER_2 = [
    'JdtNum',
    'Memo',
    'RefDate',
    'TaxDate',
    'DueDate',
    'Ref1',
    'Ref2',
    'Ref3',
    'Series',
    'TransactionCode',
  ].freeze

  HEADER_DETAIL = [
    "ParentKey",
    "LineNum",
    "AccountCode",
    "ShortName",
    "Name",
    "Debit",
    "Credit",
    "FCDebit",
    "FCCredit",
    "FCCurrency",
    "Reference1",
    "Reference2",
    "VatLine",
    "CostingCode",
    "CostingCode2",
    "CostingCode3",
    "CostingCode4",
  ].freeze

  HEADER_DETAIL_2 = [
    "JdtNum",
    "LineNum",
    "AccountCode",
    "ShortName",
    "Name",
    "Debit",
    "Credit",
    "FCDebit",
    "FCCredit",
    "FCCurrency",
    "Ref1",
    "Ref2",
    "VatLine",
    "ProfitCode",
    "OcrCode2",
    "OcrCode3",
    "OcrCode4",
  ].freeze

  HEADER_EXCEL = [
    "CUENTA CONTABLE",
    "NOMBRE DE LA CUENTA",
    "REFERENCIA 1",
    "DEBE",
    "HABER",
    "TIPO DE ASIENTO",
  ].freeze

  NO_CONTABILIZAR_INFORMATIVOS = [
    "buk_provision_bonificacion_gratificacion",
    "provision_bonificacion_extraordinaria_gratificacion_deber",
    "provision_bonificacion_extraordinaria_gratificacion_haber",
    "buk_provision_cts",
    "provision_cts_deber",
    "provision_cts_haber",
    "buk_provision_vacaciones",
    "provision_vacaciones_deber",
    "provision_vacaciones_haber",
    "buk_provision_gratificacion",
    "provision_gratificacion_deber",
    "provision_gratificacion_haber",
    "buk_sctr_pension",
    "sctr_pension_debe",
    "sctr_pension_haber",
    "buk_sctr_salud",
    "sctr_salud_debe",
    "sctr_salud_haber",
    "buk_vida_ley",
    "vida_ley_debe",
    "vida_ley_haber",
  ].freeze


  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    var_date = Variable::Utils.start_of_period_for_date(variable.start_date, variable.period_type)
    date = I18n.l(var_date, format: '%Y%m%d')
    month_year = I18n.l(var_date, format: '%m-%Y')
    year_month = I18n.l(var_date, format: '%Y-%m')

    obj_contabilidad = descartar_informativos(obj_contabilidad)

    obj_contabilidad_practicantes = obj_contabilidad.select{|l| Job::Peru::CONTRATOS_PRACTICA.include?(l.tipo_contrato)}
    obj_contabilidad_sin_practicantes = obj_contabilidad.reject{|l| Job::Peru::CONTRATOS_PRACTICA.include?(l.tipo_contrato)}

    obj_por_tipo_asiento_practicante = agrupador_asiento(obj_contabilidad_practicantes)
    obj_por_tipo_asiento_sin_practicante = agrupador_asiento(obj_contabilidad_sin_practicantes)
    tipo_contabilidad = empresa.custom_attrs["Tipo de Contabilidad"]

    case tipo_contabilidad
    when "SAP"
      libros = {}
      obj_por_tipo_asiento_sin_practicante.each do |k, obj|
        tipo_empleado_asiento = "#{k[:tipo_asiento]} #{k[:tipo_empleado]}"
        libro_cabecera = generate_header(date, month_year, tipo_empleado_asiento)
        libros["Libro_cabecera_#{tipo_empleado_asiento}".to_sym] = Exportador::Contabilidad::AccountingFile.new(contents: libro_cabecera, name_formatter: -> (name) {"CABECERA #{tipo_empleado_asiento} #{name}"})
        libro_cuerpo = generate_book(empresa, obj, tipo_empleado_asiento, month_year, year_month)
        libros["Libro_cuerpo_#{tipo_empleado_asiento}".to_sym] = Exportador::Contabilidad::AccountingFile.new(contents: libro_cuerpo, name_formatter: -> (name) {"DETALLE #{tipo_empleado_asiento} #{name}"})
      end

      obj_por_tipo_asiento_practicante.each do |k, obj|
        tipo_empleado_asiento = "Practicantes #{k[:tipo_empleado]}"
        libro_cabecera_practicante = generate_header(date, month_year, tipo_empleado_asiento)
        libros["Libro_cabecera_practicante_#{tipo_empleado_asiento}".to_sym] = Exportador::Contabilidad::AccountingFile.new(contents: libro_cabecera_practicante, name_formatter: -> (name) {"CABECERA PRACTICANTE #{tipo_empleado_asiento} #{name}"})
        libro_cuerpo_practicante = generate_book(empresa, obj, tipo_empleado_asiento, month_year, year_month)
        libros["Libro_cuerpo_practicante_#{tipo_empleado_asiento}".to_sym] = Exportador::Contabilidad::AccountingFile.new(contents: libro_cuerpo_practicante, name_formatter: -> (name) {"DETALLE PRACTICANTE #{tipo_empleado_asiento} #{name}"})
      end
      libros
    when "Excel Personalizado"
      libros = {}
      obj_por_tipo_asiento_sin_practicante.each do |k, obj|
        tipo_empleado_asiento = "#{k[:tipo_asiento]} #{k[:tipo_empleado]}"
        libro_cuerpo = generate_excel_personalizado(empresa, obj, tipo_empleado_asiento, month_year)
        libros["Libro_#{tipo_empleado_asiento}".to_sym] = Exportador::Contabilidad::AccountingFile.new(contents: libro_cuerpo, name_formatter: -> (name) {"#{tipo_empleado_asiento} #{name}"})
      end

      obj_por_tipo_asiento_practicante.each do |k, obj|
        tipo_empleado_asiento = "Practicantes #{k[:tipo_empleado]}"
        libro_cuerpo_practicante = generate_excel_personalizado(empresa, obj, tipo_empleado_asiento, month_year)
        libros["Libro_practicante_#{tipo_empleado_asiento}".to_sym] = Exportador::Contabilidad::AccountingFile.new(contents: libro_cuerpo_practicante, name_formatter: -> (name) {"PRACTICANTE #{tipo_empleado_asiento} #{name}"})
      end
      libros
    else
      super
    end
  end

  def generate_header(date, month_year, tipo_empleado_asiento)
    memo = "#{tipo_empleado_asiento} Mes #{month_year}"
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, "Cabecera"
    Exportador::BaseXlsx.crear_encabezado(sheet, HEADER, 0)
    Exportador::BaseXlsx.crear_encabezado(sheet, HEADER_2, 1)

    data = data_header(memo, date)

    Exportador::BaseXlsx.escribir_celdas sheet, [data], offset: 2
    Exportador::BaseXlsx.autofit sheet, [HEADER_2]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def generate_book(empresa, obj, tipo_empleado_asiento, month_year, year_month)
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    company_name = empresa.nombre
    sheet = Exportador::BaseXlsx.crear_hoja book, company_name
    Exportador::BaseXlsx.crear_encabezado sheet, HEADER_DETAIL, 0
    Exportador::BaseXlsx.crear_encabezado sheet, HEADER_DETAIL_2, 1
    Exportador::BaseXlsx.autofit sheet, [HEADER_DETAIL_2]
    memo = "#{tipo_empleado_asiento} Mes #{month_year}"

    agrupador = agrupador(obj, company_name)

    data = agrupador.map.with_index(0) do |(k, v), index|
      detalle_agrupacion(k, v, index, memo, year_month)
    end
    Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 2
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def generate_excel_personalizado(empresa, obj, tipo_empleado_asiento, month_year)
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    company_name = empresa.nombre
    sheet = Exportador::BaseXlsx.crear_hoja book, company_name
    Exportador::BaseXlsx.crear_encabezado(sheet, HEADER_EXCEL, 0)

    memo = "#{tipo_empleado_asiento} Mes #{month_year}"

    agrupador = obj.group_by do |l|
      {
        account: plan_cuenta(l, company_name),
        account_name: nombre_cuenta(l),
        deber_o_haber: l.deber_o_haber,
      }
    end

    data = agrupador.lazy.map do |k, v|
      [
        k[:account],
        k[:account_name],
        nil,
        k[:deber_o_haber] == 'D' ? v.sum(&:monto) : nil,
        k[:deber_o_haber] == 'C' ? v.sum(&:monto) : nil,
        memo,
      ]
    end

    Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 1
    Exportador::BaseXlsx.autofit sheet, [HEADER_EXCEL]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def generate_data(empresa, variable, obj_contabilidad, **_args)
    return [] unless obj_contabilidad.present?
    data = []

    var_date = Variable::Utils.start_of_period_for_date(variable.start_date, variable.period_type)
    date = I18n.l(var_date, format: '%Y%m%d')
    month_year = I18n.l(var_date, format: '%m-%Y')
    year_month = I18n.l(var_date, format: '%Y-%m')
    company_name = empresa.nombre

    obj_contabilidad = descartar_informativos(obj_contabilidad)

    obj_contabilidad_practicantes = obj_contabilidad.select{|l| Job::Peru::CONTRATOS_PRACTICA.include?(l.tipo_contrato)}
    obj_contabilidad_sin_practicantes = obj_contabilidad.reject{|l| Job::Peru::CONTRATOS_PRACTICA.include?(l.tipo_contrato)}

    obj_por_tipo_asiento_practicante = agrupador_asiento(obj_contabilidad_practicantes)
    obj_por_tipo_asiento_sin_practicante = agrupador_asiento(obj_contabilidad_sin_practicantes)

    obj_por_tipo_asiento_sin_practicante.each do |k, obj|
      tipo_empleado_asiento = "#{k[:tipo_asiento]} #{k[:tipo_empleado]}"
      memo = "#{tipo_empleado_asiento} Mes #{month_year}"
      data << data_header_api(memo, date)
      data << detalle_agrupacion_api(obj, company_name, memo, year_month)
    end

    obj_por_tipo_asiento_practicante.each do |k, obj|
      tipo_empleado_asiento = "Practicantes #{k[:tipo_empleado]}"
      memo = "#{tipo_empleado_asiento} Mes #{month_year}"
      data << data_header_api(memo, date)
      data << detalle_agrupacion_api(obj, company_name, memo, year_month)
    end
    data
  end

  private
    def agrupador_asiento obj
      obj.group_by do |l|
        {
          tipo_empleado: l.job_custom_attrs["Tipo de empleado contabilidad"].presence || "Sin tipo de empleado",
          tipo_asiento: l.cuenta_custom_attrs["Tipo de Asiento"].presence || "Sin tipo de asiento",
        }
      end
    end

    def data_header memo, date
      [
        "1",
        memo,
        date,
        date,
        date,
        memo,
        nil,
        nil,
        nil,
        "PLA",
      ]
    end

    def data_header_api memo, date
      [
        JdtNum: "1",
        Memo: memo,
        RefDate: date,
        TaxDate: date,
        DueDate: date,
        Ref1: memo,
        Ref2: nil,
        Ref3: nil,
        Series: nil,
        TransactionCode: "PLA",
      ]
    end

    def agrupador obj, company_name
      obj.group_by do |l|
        profitcode, ocrcode2, ocrcode3, ocrcode4 = get_cencos(l)
        {
          plan_contable: plan_cuenta(l, company_name),
          shortname: shortname(l, company_name),
          nombre_cuenta: nombre_cuenta(l),
          deber_o_haber: l.deber_o_haber,
          costing_code: profitcode,
          costing_code2: ocrcode2,
          costing_code3: ocrcode3,
          costing_code4: ocrcode4,
        }
      end
    end

    def detalle_agrupacion k, v, index, memo, year_month
      [
        "1",
        index.to_s,
        k[:plan_contable],
        k[:shortname],
        k[:nombre_cuenta],
        k[:deber_o_haber] == "D" ? v.sum(&:monto) : nil,
        k[:deber_o_haber] == "C" ? v.sum(&:monto) : nil,
        nil,
        nil,
        nil,
        memo,
        year_month,
        "tNO",
        k[:costing_code],
        k[:costing_code2],
        k[:costing_code3],
        k[:costing_code4],
      ]
    end

    def detalle_agrupacion_api obj, company_name, memo, year_month
      agrupador = agrupador(obj, company_name)
      agrupador.map.with_index(0) do |(k, v), index|
        [
          JdtNum: "1",
          LineNum: index.to_s,
          AccountCode: k[:plan_contable],
          ShortName: k[:shortname],
          Name: k[:nombre_cuenta],
          Debit: k[:deber_o_haber] == "D" ? v.sum(&:monto) : nil,
          Credit: k[:deber_o_haber] == "C" ? v.sum(&:monto) : nil,
          FCDebit: nil,
          FCCredit: nil,
          FCCurrency: nil,
          Ref1: memo,
          Ref2: year_month,
          VatLine: "tNO",
          ProfitCode: k[:costing_code],
          OcrCode2: k[:costing_code2],
          OcrCode3: k[:costing_code3],
          OcrCode4: k[:costing_code4],
        ]
      end
    end

    def plan_cuenta l, company_name
      tipo_empleado = l.job_custom_attrs["Tipo de empleado contabilidad"].to_s.upcase
      l.cuenta_custom_attrs["#{company_name} - #{tipo_empleado}"].presence || cuenta_por_afp(l, company_name)
    end

    def shortname l, company_name
      return unless l.cuenta_custom_attrs["Agrupador"] == "DNI"
      if company_name == "CONTRANS S.A.C."
        "E#{l.numero_documento}"
      else
        "E#{l.numero_documento.to_s.rjust(11, "0")}"
      end
    end

    def descartar_informativos(obj)
      obj.select do |l|
        interseccion = [l.item_code, l.nombre_cuenta] & NO_CONTABILIZAR_INFORMATIVOS
        interseccion.empty?
      end
    end

    def cuenta_por_afp l, company_name
      tipo_empleado = l.job_custom_attrs["Tipo de empleado contabilidad"].to_s.upcase
      l.cuenta_custom_attrs["AFP"].to_s.casecmp('si').zero? ? afp_method(l)&.custom_attrs&.dig("#{company_name} - #{tipo_empleado}") : l.cuenta_contable
    end

    def nombre_cuenta l
      l.cuenta_custom_attrs["AFP"].to_s.casecmp('si').zero? ? afp_method(l)&.custom_attrs&.dig("NOMBRE DE LA CUENTA CONTABLE") : l.cuenta_custom_attrs["NOMBRE DE LA CUENTA CONTABLE"]
    end

    def afp_method l
      afp = l.afp
      case afp&.upcase
      when "AFP HABITAT", "AFP INTEGRA"
        cuenta_afp(l, afp, 1)
      when "PRIMA AFP", "PROFUTURO AFP"
        cuenta_afp(l, afp, 0)
      end
    end

    def cuenta_afp l, afp, posicion
      afp_aporte = l.glosa.casecmp("afp aporte").zero?
      afp_seguro_comision = l.glosa.casecmp("afp comisión").zero? || l.glosa.casecmp("afp prima de seguros").zero?
      if afp_aporte
        afp_fondo(afp.downcase.split(" ")[posicion])
      elsif afp_seguro_comision
        afp_seguro_comision(afp.downcase.split(" ")[posicion])
      end
    end

    def afp_fondo fondo_cotizacion
      CuentaContable.cuentas_contables[:item]["afp #{fondo_cotizacion} - fondo"]
    end

    def afp_seguro_comision fondo_cotizacion
      CuentaContable.cuentas_contables[:item]["afp #{fondo_cotizacion} - seguro + comision"]
    end

    def get_cencos l
      return if l.centro_costo_custom_attrs.nil?
      profitcode = l.centro_costo_custom_attrs["Costing Code"]
      ocrcode2 = l.centro_costo_custom_attrs["Costing Code2"]
      ocrcode3 = l.centro_costo_custom_attrs["Costing Code3"]
      ocrcode4 = l.centro_costo_custom_attrs["Costing Code4"]
      [profitcode, ocrcode2, ocrcode3, ocrcode4] if l.cuenta_custom_attrs["Agrupador"] == "CENCO"
    end
end

# EXAMPLE 9
#exxis_peru.rb


# frozen_string_literal: true

#
# clase para generar centralizacion contable personalizada para exxis peru
class Exportador::Contabilidad::Peru::Personalizadas::ExxisPeru < Exportador::Contabilidad::Peru::CentralizacionContable
  def initialize
    super()
    @extension = 'xlsx'
  end

  CABECERA = [
    "ParentKey",
    "LineNum",
    "ShortName",
    "AccountCode",
    "FCCurrency",
    "Debit",
    "Credit",
    "FCDebit",
    "FCCredit",
    "DueDate",
    "TaxDate",
    "LineMemo",
    "Reference1",
  ].freeze

  CABECERA2 = [
    "JdtNum",
    "Secuencia",
    "Socio de negocio",
    "Cuenta Contable",
    "Moneda",
    "Debito_sol",
    "Credito_sol",
    "Debito_otra_moneda",
    "Credito_otra_moneda",
    "Fecha_Contable",
    "Fecha_Documento",
    "Observaciones",
    "Reference1",
  ].freeze

  TITULOS_CABECERA = [
    "JdtNum",
    "DueDate",
    "Memo",
    "ReferenceDate",
    "TaxDate",
    "TransactionCode",
  ].freeze

  TITULOS_CABECERA2 = [
    "JDT_NUM",
    "Fecha Contable",
    "Glosa del Asiento (Comentario)",
    "Fecha de Contabilizacion",
    "Fecha de Documento",
    "TransCode",
  ].freeze

  ASIENTO = {
    "NOMINA" => "PLANILLA",
    "LIQUIDACION" => "LIQUIDACION",
    "GRATIFICACION" => "PROVISION DE GRATIFICACION",
    "CTS" => "PROVISION DE CTS",
    "VACACIONES" => "PROVISION DE VACACIONES",
  }.freeze

  REF = {
    "NOMINA" => "PLAN",
    "LIQUIDACION" => "LIQ",
    "GRATIFICACION" => "PROV GRAT",
    "CTS" => "CTS",
    "VACACIONES" => "PROV VAC",
  }.freeze

  def generate_doc(_empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    books = {}
    obj_contabilidad.group_by{|l| l.cuenta_custom_attrs&.dig('Tipo de Asiento').presence || 'Otros'}.map do |k, obj|
      libro = generate_book(obj, k, variable)
      books[k] = Exportador::Contabilidad::AccountingFile.new(contents: libro, name_formatter: -> (name) {"#{name} #{k}"})
    end

    books
  end

  def generate_book(obj_contabilidad, nombre, variable)
    return unless obj_contabilidad.present?

    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    date_ddmmyyyy = date.strftime('%Y%m%d')
    month = I18n.l(date, format: '%b %Y').upcase
    memo = "#{ASIENTO[nombre]} #{month}"
    ref = "#{REF[nombre]} #{month}"


    generate_cabecera(book, date_ddmmyyyy, memo)
    sheet = Exportador::BaseXlsx.crear_hoja book, nombre
    Exportador::BaseXlsx.autofit sheet, [CABECERA]
    Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA, 0)
    Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA2, 1)


    obj_contabilidad = obj_contabilidad.group_by do |l|
      shortname, accountcode = get_shortname(l)
      {
        attrs_jdt: l.cuenta_custom_attrs["JDT_NUM"],
        shortname: shortname,
        accountcode: accountcode,
        lado: l.deber_o_haber,
      }
    end

    data = obj_contabilidad.map.with_index do |(k, v), index|

      [
        k[:attrs_jdt],
        index.to_s,
        k[:shortname],
        k[:accountcode],
        nil,
        k[:lado] == 'D' ? v.sum(&:monto) : nil,
        k[:lado] == 'C' ? v.sum(&:monto) : nil,
        nil,
        nil,
        date_ddmmyyyy,
        date_ddmmyyyy,
        memo,
        ref,
      ]
    end

    Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 2, number_format: '#.#0'
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def generate_cabecera book, fecha, memo
    date = fecha.to_s.tr("-", "")
    sheet = Exportador::BaseXlsx.crear_hoja book, "cabecera"
    Exportador::BaseXlsx.autofit sheet, [TITULOS_CABECERA]
    Exportador::BaseXlsx.crear_encabezado(sheet, TITULOS_CABECERA, 0)
    Exportador::BaseXlsx.crear_encabezado(sheet, TITULOS_CABECERA2, 1)

    data_cabecera = ["1", date, memo, date, date, "PLA"]

    Exportador::BaseXlsx.escribir_celdas sheet, [data_cabecera], offset: 2, number_format: '#.#0'
  end

  private
    def get_shortname l
      case l.cuenta_custom_attrs["Agrupador"]
      when 'DNI'
        [l.employee_custom_attrs&.dig('Código SAP'), l.cuenta_contable]
      when 'CECO'
        [nil, "#{l.cuenta_contable}-#{l.centro_costo}"]
      when "TOTALIZADO"
        [search_ruc_pe(l), search_account(l)]
      else
        [nil, nil]
      end
    end

    def search_ruc_pe(l)
      if l.cuenta_custom_attrs["AFP"].to_s.casecmp('si').zero?
        cta_afp = afp_method(l)
        "#{cta_afp.custom_attrs&.dig("P/E")}#{cta_afp.custom_attrs&.dig("RUC")}" if cta_afp.custom_attrs&.dig("RUC").present?
      else
        "#{l.cuenta_custom_attrs["P/E"]}#{l.cuenta_custom_attrs["RUC"]}" if l.cuenta_custom_attrs["RUC"].present?
      end
    end
end

# EXAMPLE 10
#ei.rb


# frozen_string_literal: true

# Archivo de Centralizacion Personalizada cliente Ei
class Exportador::Contabilidad::Peru::Personalizadas::Ei < Exportador::Contabilidad
  def initialize
    super()
    @extension = 'xlsx'
  end

  HEADER = [
    'JOURNALBATCHNUMBER',
    'LINENUMBER',
    'ACCOUNTDISPLAYVALUE',
    'ACCOUNTTYPE',
    'CASHDISCOUNT',
    'CASHDISCOUNTAMOUNT',
    'CASHDISCOUNTDATE',
    'CREDITAMOUNT',
    'CURRENCYCODE',
    'DEBITAMOUNT',
    'DEFAULTDIMENSIONDISPLAYVALUE',
    'DESCRIPTION',
    'DOCUMENT',
    'DOCUMENTDATE',
    'DUEDATE',
    'EXCHANGERATE',
    'EXCHANGERATESECONDARY',
    'INVOICE',
    'ISPOSTED',
    'ITEMSALESTAXGROUP',
    'JOURNALNAME',
    'OFFSETACCOUNTDISPLAYVALUE',
    'OFFSETACCOUNTTYPE',
    'OFFSETDEFAULTDIMENSIONDISPLAYVALUE',
    'OFFSETTEXT',
    'PAYMENTID',
    'PAYMENTMETHOD',
    'PAYMENTREFERENCE',
    'POSTINGLAYER',
    'POSTINGPROFILE',
    'QUANTITY',
    'REPORTINGCURRENCYEXCHRATE',
    'REPORTINGCURRENCYEXCHRATESECONDARY',
    'REVERSEDATE',
    'REVERSEENTRY',
    'SALESTAXCODE',
    'SALESTAXGROUP',
    'TAXEXEMPTNUMBER',
    'TEXT',
    'TRANSDATE',
    'VOUCHER',
  ].freeze

  HEADER2 = [
    'Cuenta',
    'Glosa',
    'C.C.',
    'Debe',
    'Haber',
    'Documento',
    'OT',
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    libros = {}
    obj_contabilidad.group_by{|l| l.cuenta_custom_attrs&.dig('ASIENTO') || "Sin Tipo de Asiento"}.each do |k, obj|
      tipo_asiento = k
      archivo = data_archivo(obj, variable, empresa, tipo_asiento)
      libros["Libro_#{k}"] = Exportador::Contabilidad::AccountingFile.new(contents: archivo, name_formatter: -> (name) {"#{name} #{tipo_asiento}"})
    end

    libros["reporte"] = Exportador::Contabilidad::AccountingFile.new(contents: generate_reporte(obj_contabilidad), extension: 'xlsx', name_formatter: -> (name) { "Reporte #{name} #{empresa.name}" })
    libros
  end

  def data_archivo(obj_contabilidad, variable, empresa, tipo_asiento)
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    Exportador::BaseXlsx.crear_encabezado(sheet, HEADER, 0)
    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    month = date.strftime("%m")
    month_year = I18n.l(date, format: '%B %Y').upcase
    full_date = I18n.l(date, format: "%d/%m/%Y")

    agrupador = obj_contabilidad.group_by do |l|
      {
        account: get_cuenta_contable(l),
        deber_haber: l.deber_o_haber,
      }
    end

    excel_data = agrupador.map.with_index(1) do |(k, v), index|
      [
        nil,
        index.to_s,
        k[:account],
        "Ledger",
        nil,
        ",000000",
        "1900-01-01 00:00:00",
        k[:deber_haber] == "C" ? v.sum(&:monto) : 0,
        "PEN",
        k[:deber_haber] == "D" ? v.sum(&:monto) : 0,
        nil,
        "#{tipo_asiento} #{month_year}",
        "#{month}-#{tipo_asiento}",
        full_date,
        nil,
        "100,0000000000000000",
        ",0000000000000000",
        nil,
        "No",
        nil,
        "PROVREM",
        nil,
        "Ledger",
        *Array.new(5),
        "Current",
        nil,
        ",000000",
        nil,
        ",0000000000000000",
        "1900-01-01 00:00:00",
        "No",
        *Array.new(3),
        "#{tipo_asiento} #{month_year}",
        full_date,
        nil,
      ]
    end
    Exportador::BaseXlsx.escribir_celdas sheet, excel_data, offset: 1
    Exportador::BaseXlsx.autofit sheet, [HEADER]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def generate_reporte(obj_contabilidad)
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []

    obj_contabilidad.group_by{|l| l.cuenta_custom_attrs&.dig('ASIENTO') || "Sin Tipo de Asiento"}.each do |k, obj|
      tipo_asiento = k
      sheet = Exportador::BaseXlsx.crear_hoja book, tipo_asiento
      Exportador::BaseXlsx.autofit sheet, [HEADER2]
      Exportador::BaseXlsx.crear_encabezado(sheet, HEADER2, 0)
      Exportador::BaseXlsx.escribir_celdas sheet, data_reporte(obj), offset: 1
      total_deber = obj.select(&:deber?).sum(&:monto)
      total_haber = obj.select(&:haber?).sum(&:monto)
      pie = [nil, nil, nil, total_deber, total_haber]
      Exportador::BaseXlsx.escribir_celdas sheet, [pie], offset: data_reporte(obj).size + 1
    end
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end


  def data_reporte(obj_contabilidad)
    agrupador = obj_contabilidad.sort_by(&:deber_o_haber).group_by do |l|
      {
        account: l.cuenta_contable,
        glosa: show_glosa(l).to_s.upcase,
        deber_haber: l.deber_o_haber,
        dni: get_dni(l),
        cenco: l.centro_costo,
        rut: agrupacion_rut(l),
      }
    end

    agrupador.map do |k, v|
      [
        k[:account],
        k[:glosa],
        nil,
        k[:deber_haber] == "D" ? v.sum(&:monto) : nil,
        k[:deber_haber] == "C" ? v.sum(&:monto) : nil,
        k[:dni],
        k[:cenco],
      ]
    end
  end

  private
    def get_cuenta_contable l
      case l.cuenta_custom_attrs["Agrupador"]
      when "DNI"
        rut = l.numero_documento.to_s
        dni = "#{l.cuenta_contable}.....#{rut}.#{l.centro_costo}.."
        texto = "#{l.cuenta_contable}..#{l.cuenta_custom_attrs["TEXTO"]}....#{l.centro_costo}.."
        l.cuenta_custom_attrs["DATO"].to_s.casecmp("dni").zero? ? dni : texto
      when "TOTAL"
        "#{l.cuenta_contable}.....#{l.cuenta_custom_attrs["TEXTO"]}"
      end
    end

    def show_glosa l
      l.cuenta_custom_attrs["VER DNI"].to_s.casecmp("si").zero? ? "#{l.cuenta_custom_attrs["GLOSA"]} - #{l.employee.apellidos_nombre.to_s.tr(",", "")}" : l.cuenta_custom_attrs["GLOSA"]
    end

    def get_dni l
      l.numero_documento if l.cuenta_custom_attrs["VER DNI"].to_s.casecmp("si").zero?
    end

    def agrupacion_rut obj
      obj.numero_documento.to_s if obj.cuenta_custom_attrs["Agrupador"] == "DNI"
    end
end

# EXAMPLE 11
#mri.rb


# frozen_string_literal: true

#
#Exportador de comprobante contable para MRI
class Exportador::Contabilidad::Peru::Personalizadas::Mri < Exportador::Contabilidad
  include ContabilidadPeruHelper

  def initialize
    super()
    @extension = 'xlsx'
  end

  TITULOS_PROPIO = [
    "fec_movimi",
    "mes_movimi",
    "cdo_fuente",
    "cdo_cuenta",
    "cdo_auxil1",
    "cdo_auxil2",
    "cdo_auxil3",
    "cdo_refere",
    "tip_docume",
    "num_docume",
    "monto_debe",
    "monto_habe",
    "dolar_debe",
    "dolar_habe",
    "des_movimi",
    "nom_girado",
    "cdo_usuari",
    "fec_vencim",
    "tip_docref",
    "num_docref",
    "med_pago",
    "cdo_auxil4",
    "cdo_entren",
    "tip_cambio",
    "gto_deduci",
    "cdo_moneda",
    "cdo_bieser",
    "cdo_anados",
    "ple_estado",
    "cuo_modifi",
  ].freeze

  TITULOS_SAP = [
    "Data",
    "Cuenta",
    "cta SAP",
    "Nombres",
    "Nombre SAP",
    "1er Auxiliar",
    "2do Auxiliar",
    "3er Auxiliar",
    "4to Auxiliar",
    "Glosa",
    "Debe",
    "Haber",
    "Neto",
    "Debe US$",
    "Haber US$",
    "T.Cambio",
    "Fecha",
    "Documento",
    "T.Doc",
    "Voucher",
    "Cnt",
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    case empresa.custom_attrs['Formato Contable']
    when 'SAP'
      generate_doc_sap(empresa, variable, obj_contabilidad)
    else
      generate_doc_propio(empresa, variable, obj_contabilidad)
    end
  end

  def generate_doc_sap(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    Exportador::BaseXlsx.autofit sheet, [TITULOS_SAP]
    Exportador::BaseXlsx.crear_encabezado(sheet, TITULOS_SAP, 0)

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    full_date = I18n.l(date, format: "%d/%m/%Y")
    yy_mm = I18n.l(date, format: "%y%m")

    group = obj_contabilidad.sort_by{|o| [o.cuenta_custom_attrs["Asiento"] || '']}.group_by do |l|
      afp_cod, nombre_completo, cencos = get_afp_dni(l, true)
      {
        asiento: l.cuenta_custom_attrs&.dig('Asiento'),
        cuenta_contable: get_cuenta(l, empresa),
        cuenta_sap: l.cuenta_custom_attrs["Cuenta SAP"],
        glosa: search_glosa_afp(l),
        nombre_sap: l.cuenta_custom_attrs["Nombre SAP"],
        cod_afp: afp_cod,
        cenco: cencos,
        glosa_2: nombre_completo,
        deber_haber: l.deber_o_haber,
        ref: "#{l.cuenta_custom_attrs["REF"]}#{yy_mm}00".to_s[0...8],
      }
    end

    data = group.map.with_index(1) do |(k, v), index|
      [
        k[:asiento],
        k[:cuenta_contable],
        k[:cuenta_sap],
        k[:glosa],
        k[:nombre_sap],
        k[:cod_afp],
        k[:cenco],
        nil,
        nil,
        k[:glosa_2],
        k[:deber_haber] == 'D' ? v.sum(&:monto) : 0,
        k[:deber_haber] == 'C' ? v.sum(&:monto) : 0,
        k[:deber_haber] == "D" ? v.sum(&:monto) : (v.sum(&:monto) * -1),
        0,
        0,
        0, #llevar a 3 decimales
        full_date,
        nil,
        nil,
        k[:ref],
        index,
      ]
    end

    Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 1, number_format: '###0.00'
    Exportador::BaseXlsx.formatear_columna(sheet, data, [14], "###0.000")
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def generate_doc_propio(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)

    obj_contabilidad.group_by{|l| l.cuenta_custom_attrs['Asiento'].presence || 'Otros'}.map do |k, obj|
      book = generate_book(empresa, obj, date)
      ["file_#{k}", Exportador::Contabilidad::AccountingFile.new(contents: book, name_formatter: -> (name) { "#{name}-#{k}-Formato Propio" })]
    end.to_h
  end

  def generate_book(empresa, obj_contabilidad, date)
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    Exportador::BaseXlsx.crear_encabezado(sheet, TITULOS_PROPIO, 0)
    Exportador::BaseXlsx.autofit sheet, [TITULOS_PROPIO]
    full_date = I18n.l(date, format: "%d/%m/%Y")
    date_mm = I18n.l(date, format: "%m")
    yy_mm = I18n.l(date, format: "%y%m")

    agrupado = obj_contabilidad.group_by do |l|
      codaux, cencos = get_afp_dni(l, false)
      {
        cuenta_contable: get_cuenta(l, empresa),
        cod_aux: codaux,
        cenco: cencos,
        ref: "#{l.cuenta_custom_attrs["REF"]}#{yy_mm}00".to_s[0...8],
        deber_haber: l.deber_o_haber,
        des_movi: get_movi(l),
      }
    end

    excel_data = agrupado.map do |k, v|
      [
        full_date,
        date_mm,
        "P",
        k[:cuenta_contable],
        k[:cod_aux],
        k[:cenco],
        nil,
        k[:ref],
        nil,
        nil,
        k[:deber_haber] == 'D' ? v.sum(&:monto) : 0,
        k[:deber_haber] == 'C' ? v.sum(&:monto) : 0,
        0,
        0,
        k[:des_movi],
        nil,
        "RRM",
        full_date,
        *Array.new(5),
        0,
        nil,
        "PEN",
      ]
    end
    Exportador::BaseXlsx.escribir_celdas sheet, excel_data, offset: 1
    Exportador::BaseXlsx.formatear_columna(sheet, excel_data, [23], "###0.000")
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  private
    def get_cuenta obj, empresa
      return search_account(obj) if obj.cuenta_custom_attrs["AFP"].to_s.casecmp("si").zero?
      empresa.custom_attrs["Plan Contable"] == "General" ? obj.cuenta_contable : obj.cuenta_custom_attrs[empresa.custom_attrs["Plan Contable"]]
    end

    def get_afp_dni obj, valor
      case obj.cuenta_custom_attrs["Agrupador"].upcase
      when 'DNI'
        return [obj.employee_custom_attrs["ID Colaborador"], search_cenco(obj).presence || obj.employee_custom_attrs["ID Contable"]] unless valor
        [obj.numero_documento.to_s, obj.employee.nombre_completo, search_cenco(obj).presence || obj.employee_custom_attrs["ID Contable"]] unless valor
      when 'TOTAL'
        return get_afp(obj) unless valor
        [get_afp(obj), search_glosa_afp(obj)]
      end
    end

    def get_movi obj
      return "#{search_glosa_afp(obj)} #{obj.centro_costo_custom_attrs["Nombre CENCO"]}" if obj.cuenta_custom_attrs["Centro Costo"].to_s.casecmp("si").zero?
      obj.cuenta_custom_attrs["Agrupador"] == "DNI" ? "#{search_glosa_afp(obj)} #{obj.employee.nombre_completo}" : search_glosa_afp(obj)
    end

    def get_afp obj
      afp_method(obj)&.custom_attrs&.dig("Cod AFP") if obj.cuenta_custom_attrs["AFP"].to_s.casecmp("si").zero?
    end
end

# EXAMPLE 12
#treid_peru_s_a_c.rb


# rubocop:disable Buk/FileNameClass
# Clase para generar centralizacion contable para cliente Treid Peru SAC
class Exportador::Contabilidad::Peru::Personalizadas::TreidPeruSAC < Exportador::Contabilidad::Peru::CentralizacionContable

  NO_CONTABILIZAR_PROVISIONES = [
    "buk_provision_gratificacion",
    "buk_provision_vacaciones",
    "buk_provision_cts",
    "buk_provision_bonificacion_gratificacion",
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?
    obj_sin_prov = descartar_informativos(obj_contabilidad)

    centra_contable = Exportador::Contabilidad::Peru::CentralizacionContable.new
    centra_contable.generate_doc(empresa, variable, obj_sin_prov)
  end
  private
    def descartar_informativos(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_PROVISIONES.include?(l.item_code)
      end
    end
end
# rubocop:enable Buk/FileNameClass

# EXAMPLE 13
#cipesa.rb


# frozen_string_literal: true

#Clase para la centralizacion personaliza cliente Cipesa
class Exportador::Contabilidad::Peru::Personalizadas::Cipesa < Exportador::Contabilidad::Peru::CentralizacionContable

  def generate_data(empresa, variable, obj_contabilidad, **_args)
    return [] if obj_contabilidad.nil? || obj_contabilidad.empty?

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    end_date = I18n.l(date, format: "%d/%m/%Y")
    annio_mes = I18n.l(date, format: '%Y%m')
    mes_annio = I18n.l(date, format: "%m.%Y")
    month_year = I18n.l(date, format: '%B %Y').upcase
    tipo_cambio = kpi_dolar(variable.id, empresa.id, 'tipo_de_cambio')

    grouped = obj_contabilidad.group_by{|l| l.cuenta_custom_attrs["Tipo de Asiento"].presence || "Sin clasificar"}

    grouped.map do |k, obj|
      tipo_asiento = k
      generate_api_cuerpo(obj, tipo_asiento, end_date, annio_mes, mes_annio, month_year, tipo_cambio)
    end
  end

  private

    def generate_api_cuerpo(obj_contabilidad, tipo_asiento, end_date, annio_mes, mes_annio, month_year, tipo_cambio)
      agrupador = obj_contabilidad.group_by do |l|
        {
          cuenta_contable: search_account(l),
          comprobante: l.cuenta_custom_attrs['Comprobante'],
          tipo_anexo: l.cuenta_custom_attrs['Tipo de Anexo'],
          codigo_anexo: search_ruc(l),
          deber_o_haber: l.deber_o_haber,
          cenco: search_cenco(l),
        }
      end

      agrupador.map do |k, v|
        {
          "CUENTA CONTABLE": k[:cuenta_contable],
          "AÑO Y MES DE PROCESO": annio_mes,
          "SUBDIARIO": '06',
          "COMPROBANTE": k[:comprobante],
          "FECHA DEL DOCUMENTO": end_date,
          "TIPO DE ANEXO": k[:tipo_anexo],
          "CODIGO DE ANEXO": k[:codigo_anexo],
          "TIPO DE DOCUMENTO": 'PL',
          "SERIE Y NUMERO DEL DOCUMENTO": mes_annio,
          "FECHA DE VENCIMIENTO DEL DOCUMENTO": end_date,
          "MONEDA DEL DOCUMENTO": 'MN',
          "IMPORTE TOTAL DEL DOCUMENTO": v.sum(&:monto),
          "TIPO DE CONVERSION DEL TIPO DE CAMBIO": 'VTA',
          "FECHA DE REGISTRO": end_date,
          "TIPO DE CAMBIO": tipo_cambio,
          "GLOSA": "#{tipo_asiento} #{month_year}",
          "CENTRO DE COSTO": k[:cenco],
          "GLOSA DEL MOVIMIENTO": "#{tipo_asiento} #{month_year}",
          "DOC. ANULADO": '0',
          "DEBE O HABER": k[:deber_haber] == "D" ? "D" : "H",
          "MEDIO DE PAGO": "",
          "NRO FILE": "",
          "FLUJO DE EFECTIVO": "",
        }
      end
    end
end

# EXAMPLE 14
#bsale.rb


# frozen_string_literal: true

#
#Exportador de comprobante contable para Bsale
class Exportador::Contabilidad::Peru::Personalizadas::Bsale < Exportador::Contabilidad::Peru::CentralizacionContable
  def initialize
    super()
    @extension = 'xlsx'
  end

  TITULOS_PROPIO = [
    "fec_movimi",
    "mes_movimi",
    "cdo_fuente",
    "cdo_cuenta",
    "cdo_auxil1",
    "cdo_auxil2",
    "cdo_auxil3",
    "cdo_refere",
    "tip_docume",
    "num_docume",
    "monto_debe",
    "monto_habe",
    "dolar_debe",
    "dolar_habe",
    "des_movimi",
    "nom_girado",
    "cdo_usuari",
    "fec_movimi",
    "tip_docref",
    "num_docref",
    "med_pago",
    "cdo_auxil4",
    "cdo_entren",
    "tip_cambio",
    "gto_deduci",
    "cdo_moneda",
    "cdo_bieser",
    "cdo_anados",
    "ple_estado",
    "cuo_modifi",
  ].freeze

  NO_CONTABILIZAR_INFORMATIVOS = [
    "provision_bonificacion_extraordinaria_gratificacion_deber",
    "provision_bonificacion_extraordinaria_gratificacion_haber",
    "provision_gratificacion_haber",
    "provision_gratificacion_deber",
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)

    obj_contabilidad = descartar_informativos(obj_contabilidad)

    obj_contabilidad.group_by{|l| l.cuenta_custom_attrs['Asiento'].presence || 'Otros'}.map do |k, obj|
      book = generate_book(empresa, variable, obj, date)
      ["file_#{k}", Exportador::Contabilidad::AccountingFile.new(contents: book, name_formatter: -> (name) { "#{name}-#{k}-Formato Propio" })]
    end.to_h
  end

  def generate_book(empresa, variable, obj_contabilidad, date)
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    Exportador::BaseXlsx.crear_encabezado(sheet, TITULOS_PROPIO, 0)
    Exportador::BaseXlsx.autofit sheet, [TITULOS_PROPIO]
    full_date = I18n.l(date, format: "%d/%m/%Y")
    date_mm = I18n.l(date, format: "%m")
    date_mm_yyyy = I18n.l(date, format: "%m-%Y")
    tipo_cambio = kpi_dolar(variable.id, empresa.id)

    agrupado = obj_contabilidad.sort_by{|obj| [obj.cuenta_custom_attrs&.dig("cdo_refere")]}.group_by do |l|
      {
        cuenta_contable: search_account_afp_plan_contable_dinamico(l, "job").to_s,
        cod_aux: l.cuenta_custom_attrs["cdo_auxil1"],
        glosa: l.cuenta_custom_attrs["Agrupador"] == "AFP" ? "AFP" : search_glosa(l),
        ref: l.cuenta_custom_attrs["cdo_refere"],
        deber_haber: l.deber_o_haber,
        cdo_usuari: l.cuenta_custom_attrs["cdo_usuari"],
      }
    end

    excel_data = agrupado.map do |k, v|
      [
        full_date,
        date_mm,
        "P",
        k[:cuenta_contable],
        k[:cod_aux],
        nil,
        nil,
        k[:ref],
        "PL",
        date_mm_yyyy,
        k[:deber_haber] == 'D' ? v.sum(&:monto) : 0,
        k[:deber_haber] == 'C' ? v.sum(&:monto) : 0,
        k[:deber_haber] == 'D' ? v.sum(&:monto) / tipo_cambio : 0,
        k[:deber_haber] == 'C' ? v.sum(&:monto) / tipo_cambio : 0,
        k[:glosa],
        nil,
        k[:cdo_usuari],
        full_date,
        nil,
        nil,
        nil,
        nil,
        nil,
        tipo_cambio,
        nil,
        "PEN",
      ]
    end
    Exportador::BaseXlsx.escribir_celdas sheet, excel_data, offset: 1
    Exportador::BaseXlsx.formatear_columna(sheet, excel_data, [23], "###0.##############")
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  private

    def descartar_informativos(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_INFORMATIVOS.include?(l.nombre_cuenta)
      end
    end

end

# EXAMPLE 15
#puerto92.rb


# Archivo de Centralizacion Personalizada cliente Puerto92 Perú
class Exportador::Contabilidad::Peru::Personalizadas::Puerto92 < Exportador::Contabilidad
  def initialize
    super()
    @extension = 'xlsx'
  end
  TITULOS = ['Campo',
             'Sub Diario',
             'Número de Comprobante',
             'Fecha de Comprobante',
             'Código de Moneda',
             'Glosa Principal',
             'Tipo de Cambio',
             'Tipo de Conversión',
             'Flag de Conversión de Moneda',
             'Fecha Tipo de Cambio',
             'Cuenta Contable',
             'Código de Anexo',
             'Código de Centro de Costo',
             'Debe / Haber',
             'Importe Original',
             'Importe en Dólares',
             'Importe en Soles',
             'Tipo de Documento',
             'Número de Documento',
             'Fecha de Documento',
             'Fecha de Vencimiento',
             'Código de Area',
             'Glosa Detalle',
             'Código de Anexo Auxiliar',
             'Medio de Pago',
             'Tipo de Documento de Referencia',
             'Número de Documento Referencia',
             'Fecha Documento Referencia',
             'Nro Máq. Registradora Tipo Doc. Ref.',
             'Base Imponible Documento Referencia',
             'IGV Documento Provisión',
             'Tipo Referencia en estado MQ',
             'Número Serie Caja Registradora',
             'Fecha de Operación',
             'Tipo de Tasa',
             'Tasa Detracción/Percepción',
             'Importe Base Detracción/Percepción Dólares',
             'Importe Base Detracción/Percepción Soles',
             'Tipo Cambio para F',
             'Importe de IGV sin derecho crédito fiscal',].freeze
  def generate_doc(_empresa, variable, obj_contabilidad)
    # book
    return unless obj_contabilidad.present?
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    #Hojas
    sheet_planilla = Exportador::BaseXlsx.crear_hoja book, "PROVISION PLANILLA"
    sheet_vacaciones = Exportador::BaseXlsx.crear_hoja book, "PROVISION VACACIONES"
    sheet_gratificacion = Exportador::BaseXlsx.crear_hoja book, "PROVISION GRATIFICACION"
    sheet_provision = Exportador::BaseXlsx.crear_hoja book, "PROVISION CTS"
    sheet_liquidacion = Exportador::BaseXlsx.crear_hoja book, "LIQUIDACION POR PAGAR"
    # variables
    fecha = variable.end_date.strftime("%d-%m-%y")
    mes = variable.end_date.strftime('%m')
    anio = variable.end_date.strftime('%Y')
    Exportador::BaseXlsx.crear_encabezado(sheet_planilla, TITULOS, 0)
    Exportador::BaseXlsx.crear_encabezado(sheet_vacaciones, TITULOS, 0)
    Exportador::BaseXlsx.crear_encabezado(sheet_gratificacion, TITULOS, 0)
    Exportador::BaseXlsx.crear_encabezado(sheet_provision, TITULOS, 0)
    Exportador::BaseXlsx.crear_encabezado(sheet_liquidacion, TITULOS, 0)
    #------------------Agrupacionnes-----------------------
    group_planilla = metodo_agrupar(1, obj_contabilidad, mes, anio)
    group_provisiones_v = metodo_agrupar(2, obj_contabilidad, mes, anio)
    group_gratificaciones = metodo_agrupar(3, obj_contabilidad, mes, anio)
    group_cts = metodo_agrupar(4, obj_contabilidad, mes, anio)
    group_liquidacion = metodo_agrupar(5, obj_contabilidad, mes, anio)
    #------------------------------------------------------
    group_planilla.map.with_index(1) do |(k, v), index|
      data_planilla = print_agrupados(k, v, fecha, anio, mes)
      Exportador::BaseXlsx.escribir_celdas sheet_planilla, [data_planilla], offset: index, number_format: '#,##0.00'
    end
    metodo_imprimir_detalle(1, obj_contabilidad, anio, group_planilla.size + 1, sheet_planilla, mes, fecha)
    #--------------------------------------
    group_provisiones_v.map.with_index(1) do |(k, v), index|
      data_vacaciones = print_agrupados(k, v, fecha, anio, mes)
      Exportador::BaseXlsx.escribir_celdas sheet_vacaciones, [data_vacaciones], offset: index, number_format: '#,##0.00'
    end
    metodo_imprimir_detalle(2, obj_contabilidad, anio, group_provisiones_v.size + 1, sheet_vacaciones, mes, fecha)
    #-----------------------------------------
    group_gratificaciones.map.with_index(1) do |(k, v), index|
      data_gratificacion = print_agrupados(k, v, fecha, anio, mes)
      Exportador::BaseXlsx.escribir_celdas sheet_gratificacion, [data_gratificacion], offset: index, number_format: '#,##0.00'
    end
    metodo_imprimir_detalle(3, obj_contabilidad, anio, group_gratificaciones.size + 1, sheet_gratificacion, mes, fecha)
    #-----------------------------------------
    group_cts.map.with_index(1) do |(k, v), index|
      data_provision = print_agrupados(k, v, fecha, anio, mes)
      Exportador::BaseXlsx.escribir_celdas sheet_provision, [data_provision], offset: index, number_format: '#,##0.00'
    end
    metodo_imprimir_detalle(4, obj_contabilidad, anio, group_cts.size + 1, sheet_provision, mes, fecha)
    #-----------------------------------------
    group_liquidacion.map.with_index(1) do |(k, v), index|
      data_liquidacion = print_agrupados(k, v, fecha, anio, mes)
      Exportador::BaseXlsx.escribir_celdas sheet_liquidacion, [data_liquidacion], offset: index, number_format: '#,##0.00'
    end
    metodo_imprimir_detalle(5, obj_contabilidad, anio, group_liquidacion.size + 1, sheet_liquidacion, mes, fecha)
    Exportador::BaseXlsx.autofit(sheet_planilla, [TITULOS])
    Exportador::BaseXlsx.autofit(sheet_vacaciones, [TITULOS])
    Exportador::BaseXlsx.autofit(sheet_gratificacion, [TITULOS])
    Exportador::BaseXlsx.autofit(sheet_provision, [TITULOS])
    Exportador::BaseXlsx.autofit(sheet_liquidacion, [TITULOS])
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end
  def create_lineas_liquidacion(liquidacions, **args)
    ::Contabilidad::Peru::LineasLiquidacionesService.new(liquidacions, **args)
  end

  private
    def print_detalle l, fecha, mes, anio
      [
        nil, #A
        "35", #B
        "#{mes}#{l.cuenta_custom_attrs&.dig("Correlativo")}", #C
        fecha, #D
        "MN", #E
        "#{l.cuenta_custom_attrs&.dig("Glosa Principal")} #{mes}-#{anio}", #F
        "0", #G
        "V", #H
        "S", #I
        nil, #J
        l.cuenta_contable, #K
        search_ruc(l), #L
        cc(l), #M
        l.deber_o_haber == "D" ? "D" : "H", #N
        l.monto.to_i, #O
        nil, #P
        nil, #Q
        "PL", #R
        "#{anio}-#{mes}", #S
        fecha, #T
        fecha, #U
        nil, #V
        "#{l.cuenta_custom_attrs&.dig("Glosa Principal")} #{mes}-#{anio}", #W
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
      ]
    end
    def cc object
      object.cuenta_custom_attrs&.dig("Centro de Costo")&.parameterize == "si" ? object.centro_costo : nil
    end
    def metodo_imprimir_detalle hoja, obj_contabilidad, anio, index, sheet, mes, fecha
      array_asiento = {
        1 => "PROVISION PLANILLA",
        2 => "PROVISION VACACIONES",
        3 => "PROVISION GRATIFICACION",
        4 => "PROVISION CTS",
        5 => "LIQUIDACION POR PAGAR",
      }
      asiento_detalle = obj_contabilidad.select{|o| o.cuenta_custom_attrs&.dig("Glosa Principal") == array_asiento[hoja] && o.cuenta_custom_attrs&.dig("Agrupación") != "RUC"}
      asiento_detalle.each do |p|
        data = print_detalle(p, fecha, mes, anio)
        Exportador::BaseXlsx.escribir_celdas sheet, [data], offset: index, number_format: "#,##0"
        index += 1
      end
    end
    def search_ruc object
      case object.cuenta_custom_attrs&.dig('Rut')&.to_s&.upcase&.squish
      when 'AFP'
        object.ruc_afp
      when 'DNI'
        object.numero_documento&.humanize
      when 'SUNAT'
        "20131312955"
      else
        object.cuenta_custom_attrs&.dig('Rut')
      end
    end
    def print_agrupados k, v, fecha, anio, mes
      [
        nil, #A
        "35", #B
        k[:correlativo], #C
        fecha, #D
        "MN", #E
        k[:glosa], #F
        "0", #G
        "V", #H
        "S", #I
        nil, #J
        k[:cuenta_contable], #K
        k[:ruc], #L
        k[:centro_costo], #M
        k[:deber_o_haber] == "D" ? "D" : "H", #N
        v.sum(&:monto), #O
        nil, #P
        nil, #Q
        "PL", #R
        "#{anio}-#{mes}", #S
        fecha, #T
        fecha, #U
        nil, #V
        k[:glosa], #W
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
      ]
    end
    def metodo_agrupar hoja, obj_contabilidad, mes, anio
      array_asiento = {
        1 => "PROVISION PLANILLA",
        2 => "PROVISION VACACIONES",
        3 => "PROVISION GRATIFICACION",
        4 => "PROVISION CTS",
        5 => "LIQUIDACION POR PAGAR",
      }
      asiento = obj_contabilidad.select{|o| o.cuenta_custom_attrs&.dig("Glosa Principal") == array_asiento[hoja] && o.cuenta_custom_attrs&.dig("Agrupación") == "RUC"}
      asiento.group_by do |o|
        {
          correlativo: "#{mes}#{o.cuenta_custom_attrs&.dig("Correlativo")}",
          glosa: "#{o.cuenta_custom_attrs&.dig("Glosa Principal")} #{mes}-#{anio}",
          cuenta_contable: o.cuenta_contable,
          colaborador: o.numero_documento,
          ruc: search_ruc(o),
          centro_costo: cc(o),
          deber_o_haber: o.deber_o_haber,
        }
      end
    end
end

# EXAMPLE 16
#arie.rb


# frozen_string_literal: true

#
# clase para generar centralizacion contable personalizada para arie
class Exportador::Contabilidad::Peru::Personalizadas::Arie < Exportador::Contabilidad::Peru::CentralizacionContable
  def initialize
    super()
    @extension = 'xlsx'
  end

  CABECERA = [
    [
      "Campo",
      "Sub Diario",
      "Número de Comprobante",
      "Fecha de Comprobante",
      "Código de Moneda",
      "Glosa Principal",
      "Tipo de Cambio",
      "Tipo de Conversión",
      "Flag de Conversión de Moneda",
      "Fecha Tipo de Cambio",
      "Cuenta Contable",
      "Código de Anexo",
      "Código de Centro de Costo",
      "Debe / Haber",
      "Importe Original",
      "Importe en Dólares",
      "Importe en Soles",
      "Tipo de Documento",
      "Número de Documento",
      "Fecha de Documento",
      "Fecha de Vencimiento",
      "Código de Area",
      "Glosa Detalle",
      "Código de Anexo Auxiliar",
      "Medio de Pago",
      "Tipo de Documento de Referencia",
      "Número de Documento Referencia",
      "Fecha Documento Referencia",
      "Nro Máq. Registradora Tipo Doc. Ref.",
      "Base Imponible Documento Referencia",
      "IGV Documento Provisión",
      "Tipo Referencia en estado MQ",
      "Número Serie Caja Registradora",
      "Fecha de Operación",
      "Tipo de Tasa",
      "Tasa Detracción/Percepción",
      "Importe Base Detracción/Percepción Dólares",
      "Importe Base Detracción/Percepción Soles",
      "Tipo Cambio para 'F'",
      "Importe de IGV sin derecho crédito fiscal",
      "Tasa IGV",
    ],
    [
      "Restricciones",
      "Ver T.G. 02",
      "Los dos primeros dígitos son el mes y los otros 4 siguientes un correlativo",
      "",
      "Ver T.G. 03",
      "",
      "Llenar  solo si Tipo de Conversión es 'C'. Debe estar entre >=0 y <=9999.999999",
      "Solo: 'C'= Especial, 'M'=Compra, 'V'=Venta , 'F' De acuerdo a fecha",
      "Solo: 'S' = Si se convierte, 'N'= No se convierte",
      "Si  Tipo de Conversión 'F'",
      "Debe existir en el Plan de Cuentas",
      "Si Cuenta Contable tiene seleccionado Tipo de Anexo, debe existir en la tabla de Anexos",
      "Si Cuenta Contable tiene habilitado C. Costo, Ver T.G. 05",
      "'D' ó 'H'",
      "Importe original de la cuenta contable. Obligatorio, debe estar entre >=0 y <=99999999999.99",
      "Importe de la Cuenta Contable en Dólares. Obligatorio si Flag de Conversión de Moneda esta en 'N', debe estar entre >=0 y <=99999999999.99",
      "Importe de la Cuenta Contable en Soles. Obligatorio si Flag de Conversión de Moneda esta en 'N', debe estra entre >=0 y <=99999999999.99",
      "Si Cuenta Contable tiene habilitado el Documento Referencia Ver T.G. 06",
      "Si Cuenta Contable tiene habilitado el Documento Referencia Incluye Serie y Número",
      "Si Cuenta Contable tiene habilitado el Documento Referencia",
      "Si Cuenta Contable tiene habilitada la Fecha de Vencimiento",
      "Si Cuenta Contable tiene habilitada el Area. Ver T.G. 26",
      "",
      "Si Cuenta Contable tiene seleccionado Tipo de Anexo Referencia",
      "Si Cuenta Contable tiene habilitado Tipo Medio Pago. Ver T.G. 'S1'",
      "Si Tipo de Documento es 'NA' ó 'ND' Ver T.G. 06",
      "Si Tipo de Documento es 'NC', 'NA' ó 'ND', incluye Serie y Número",
      "Si Tipo de Documento es 'NC', 'NA' ó 'ND'",
      "Si Tipo de Documento es 'NC', 'NA' ó 'ND'. Solo cuando el Tipo Documento de Referencia 'TK'",
      "Si Tipo de Documento es 'NC', 'NA' ó 'ND'",
      "Si Tipo de Documento es 'NC', 'NA' ó 'ND'",
      "Si la Cuenta Contable tiene Habilitado Documento Referencia 2 y  Tipo de Documento es 'TK'",
      "Si la Cuenta Contable teien Habilitado Documento Referencia 2 y  Tipo de Documento es 'TK'",
      "Si la Cuenta Contable tiene Habilitado Documento Referencia 2. Cuando Tipo de Documento es 'TK', consignar la fecha de emision del ticket",
      "Si la Cuenta Contable tiene configurada la Tasa:  Si es '1' ver T.G. 28 y '2' ver T.G. 29",
      "Si la Cuenta Contable tiene conf. en Tasa:  Si es '1' ver T.G. 28 y '2' ver T.G. 29. Debe estar entre >=0 y <=999.99",
      "Si la Cuenta Contable tiene configurada la Tasa. Debe ser el importe total del documento y estar entre >=0 y <=99999999999.99",
      "Si la Cuenta Contable tiene configurada la Tasa. Debe ser el importe total del documento y estar entre >=0 y <=99999999999.99",
      "Especificar solo si Tipo Conversión es 'F'. Se permite 'M' Compra y 'V' Venta.",
      "Especificar solo para comprobantes de compras con IGV sin derecho de crédito Fiscal. Se detalle solo en la cuenta 42xxxx",
      "Obligatorio para comprobantes de compras, valores validos 0,10,18.",
    ],
    [
      "Tamaño/Formato",
      "4 Caracteres",
      "6 Caracteres",
      "dd/mm/aaaa",
      "2 Caracteres",
      "40 Caracteres",
      "Numérico 11, 6",
      "1 Caracteres",
      "1 Caracteres",
      "dd/mm/aaaa",
      "12 Caracteres",
      "18 Caracteres",
      "",
      "1 Carácter",
      "Numérico 14,2",
      "Numérico 14,2",
      "Numérico 14,2",
      "2 Caracteres",
      "20 Caracteres",
      "dd/mm/aaaa",
      "dd/mm/aaaa",
      "3 Caracteres",
      "30 Caracteres",
      "18 Caracteres",
      "8 Caracteres",
      "2 Caracteres",
      "20 Caracteres",
      "dd/mm/aaaa",
      "20 Caracteres",
      "Numérico 14,2",
      "Numérico 14,2",
      "'MQ'",
      "15 caracteres",
      "dd/mm/aaaa",
      "5 Caracteres",
      "Numérico 14,2",
      "Numérico 14,2",
      "Numérico 14,2",
      "1 Caracter",
      "Numérico 14,2",
      "Numérico 14,2",
    ],
  ].freeze

  NO_CONTABILIZAR_INFORMATIVOS = [
    "buk_provision_vacaciones",
    "buk_provision_gratificacion",
    "buk_provision_cts",
    "buk_provision_bonificacion_gratificacion",
    "buk_vida_ley",
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    obj_contabilidad = descartar_informativos(obj_contabilidad)

    books = {}
    obj_contabilidad.group_by{|l| l.cuenta_custom_attrs&.dig('Glosa Principal').presence || 'Otros'}.each do |k, obj|
      book = generate_book(empresa, variable, obj, k)
      books[k] = Exportador::Contabilidad::AccountingFile.new(contents: book, name_formatter: -> (name) {"#{name} - #{k}"})
    end
    books
  end

  def generate_book(empresa, variable, obj_contabilidad, attr_glosa_principal)
    return unless obj_contabilidad.present?

    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    Exportador::BaseXlsx.autofit sheet, [CABECERA[0]]
    Exportador::BaseXlsx.escribir_celdas sheet, CABECERA, offset: 0

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)

    date_mm = I18n.l(date, format: '%m')
    date_month_year = I18n.l(date, format: '%B %Y').upcase
    date_ddmmyyyy = I18n.l(date, format: '%d/%m/%Y')

    numero_de_comprobante = "#{date_mm}#{empresa.custom_attrs['Correlativo']}"

    glosa_principal = "#{attr_glosa_principal} #{date_month_year}"
    tipo_de_cambio = empresa.custom_attrs['Tipo de cambio'].to_f
    tipo_de_documento = "PL" if attr_glosa_principal == 'PLANILLA'

    glosa_detalle = "#{attr_glosa_principal} #{date_month_year}"

    obj_contabilidad = obj_contabilidad.group_by do |l|
      {
        cuenta_contable: search_account_afp_plan_contable_dinamico(l, 'employee'),
        codigo_de_anexo: get_codigo_anexo(l),
        codigo_de_centro_de_costo: get_cenco(l),
        debe_haber: l.deber_o_haber,
        fecha_de_vencimiento: l.cuenta_custom_attrs['Vencimiento'] == 'Si' ? date_ddmmyyyy : "",
      }
    end

    data = obj_contabilidad.map do |k, v|
      monto = v.sum(&:monto)
      [
        '',
        '35',
        numero_de_comprobante,
        date_ddmmyyyy,
        'MN',
        glosa_principal,
        tipo_de_cambio,
        'V',
        'S',
        date_ddmmyyyy,
        k[:cuenta_contable],
        k[:codigo_de_anexo],
        k[:codigo_de_centro_de_costo].to_s,
        k[:debe_haber] == 'C' ? 'H' : 'D',
        monto,
        monto * tipo_de_cambio,
        monto,
        tipo_de_documento,
        date_month_year,
        date_ddmmyyyy,
        k[:fecha_de_vencimiento],
        nil,
        glosa_detalle,
      ]
    end

    Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 3, number_format: '#,##0.00'

    data_header = Array.new(2, [''] * data[0].size)
    Exportador::BaseXlsx.formatear_columna sheet, data_header + data, [6], '#,##0.000'
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  private

    def get_codigo_anexo(l)
      return "CAPACITACION" if l.centro_costo_custom_attrs&.dig('Capacitación') == 'Si'

      afp = afp_method(l) if l.cuenta_custom_attrs["AFP"].to_s.upcase.squish == "SI"
      codigo_anexo = afp&.custom_attrs&.dig('Codigo de Anexo').presence || l.cuenta_custom_attrs['Codigo de Anexo']

      case codigo_anexo
      when "DNI"
        l.numero_documento
      when "SEDE"
        l.job_custom_attrs&.dig("Sede")
      when "VARIOS"
        "VARIOS"
      when "RAZON"
        afp&.custom_attrs&.dig('Razon').presence || l.cuenta_custom_attrs['Razon']
      when "CAPACITACION Y VENTAS"
        "CAPACITACION Y VENTAS"
      when "GLOSA"
        l.glosa
      else
        ""
      end
    end

    def descartar_informativos(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_INFORMATIVOS.include?(l.item_code)
      end
    end

    def get_cenco obj
      return if obj.cuenta_custom_attrs&.dig("Agrupador").to_s.casecmp("total").zero?
      obj.cuenta_custom_attrs["Centro de Costo"].to_s.casecmp("personalizado").zero? ? obj.cuenta_custom_attrs["CECO Personalizado"] : obj.centro_costo
    end
end

# EXAMPLE 17
#binswanger.rb


# frozen_string_literal: true

#
# clase para generar centralizacion contable personalizada para binswanger
class Exportador::Contabilidad::Peru::Personalizadas::Binswanger < Exportador::Contabilidad::Peru::CentralizacionContable
  require 'csv'
  def initialize
    super()
    @extension = 'txt'
  end

  HEAD = [
    "JdtNum",
    "ReferenceDate",
    "Reference",
    "Memo",
    "TransactionCode",
  ].freeze

  HEAD2 = [
    "JDT_NUM",
    "RefDate",
    "Referencia 1",
    "Glosa del Asiento",
    "TransCode",
  ].freeze

  DATA_HEAD = [
    "ParentKey",
    "Line_ID",
    "ShortName",
    "NroCuenta",
    "AccountCode",
    "Debit",
    "Credit",
    "ProjectCode",
    "CostingCode",
    "CostingCode2",
    "CostingCode3",
    "U_STR_TIPP",
    "U_STR_NROP",
    "U_ItmsGrpCod",
    "LineMemo",
  ].freeze

  DATA_HEAD2 = [
    "JdtNum",
    "Line_ID",
    "ShortName",
    "Numero Cuenta",
    "Account",
    "Debit",
    "Credit",
    "CECO",
    "Tipo de Negocio",
    "Tipo de Servicio",
    "Clase 9",
    "Tipo Presupuesto",
    "Número Presupuesto",
    "Grupo de Articulo",
    "LineMemo",
  ].freeze

  def generate_doc(_empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?
    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    date_ddmmyyyy = date.strftime('%Y%m%d')

    books = {}
    obj_contabilidad.group_by{|l| l.cuenta_custom_attrs&.dig('TIPO ASIENTO').presence || 'Otros'}.map do |tipo_asiento, obj|
      head = generate_head(tipo_asiento, date_ddmmyyyy)
      document = generate_document(obj)
      books["Cabecera - #{tipo_asiento}"] = Exportador::Contabilidad::AccountingFile.new(contents: head, name: "Cabecera - #{tipo_asiento}")
      books["Detalle - #{tipo_asiento}"] = Exportador::Contabilidad::AccountingFile.new(contents: document, name: "Detalle - #{tipo_asiento}")
    end
    books
  end

  def generate_head tipo_asiento, date_ddmmyyyy
    CSV.generate(col_sep: "\t") do |csv|
      csv << HEAD
      csv << HEAD2
      csv << [
        "1",
        date_ddmmyyyy,
        "PLL #{date_ddmmyyyy}",
        "#{tipo_asiento} #{date_ddmmyyyy}",
        "PLL",
      ]
    end
  end

  def generate_document obj
    CSV.generate(col_sep: "\t") do |csv|
      csv << DATA_HEAD
      csv << DATA_HEAD2
      agrupador = obj.group_by do |l|
        agrupador(l)
      end
      agrupador.map.with_index(1) do |(k, v), index|
        csv << [
          "1",
          index,
          k[:shortname],
          k[:cuenta_contable],
          k[:AccountCode],
          k[:lado] == "D" ? v.sum(&:monto) : 0,
          k[:lado] == "C" ? v.sum(&:monto) : 0,
          k[:centro_costo],
          k[:CostingCode],
          k[:CostingCode2],
          k[:CostingCode3],
          k[:U_STR_TIPP],
          k[:U_STR_NROP],
          "100",
          k[:glosa],
        ]
      end
    end
  end

  def agrupador l
    {
      shortname: l.cuenta_custom_attrs["ShortName"],
      cuenta_contable: l.cuenta_contable,
      AccountCode: l.cuenta_custom_attrs["AccountCode"],
      lado: l.deber_o_haber,
      centro_costos: l.centro_costo,
      CostingCode: l.cuenta_custom_attrs["CostingCode"],
      CostingCode2: l.cuenta_custom_attrs["CostingCode2"],
      CostingCode3: l.cuenta_custom_attrs["CostingCode3"],
      U_STR_TIPP: l.cuenta_custom_attrs["U_STR_TIPP"],
      U_STR_NROP: l.job_custom_attrs["U_STR_NROP"],
      glosa: l.glosa,
    }
  end
end

# EXAMPLE 18
#contacto.rb


# frozen_string_literal: true

#
# clase para generar centralizacion contable personalizada para contacto
class Exportador::Contabilidad::Peru::Personalizadas::Contacto < Exportador::Contabilidad::Peru::CentralizacionContable
  def initialize
    super()
    @extension = 'xlsx'
  end

  CABECERA = [
    'fec_movimi',
    'mes_movimi',
    'cdo_fuente',
    'cdo_cuenta',
    'cdo_auxil1',
    'cdo_auxil2',
    'cdo_auxil3',
    'Codigo de Referencia',
    'tip_docume',
    'num_docume',
    'monto_debe',
    'monto_habe',
    'dolar_debe',
    'dolar_habe',
    'des_movimi',
    'nom_girado',
    'cdo_usuari',
    'fec_vencim',
    'tip_docref',
    'num_docref',
    'med_pago',
    'cdo_auxil4',
    'cdo_entren',
    'tip_cambio',
    'gto_deduci',
    'cdo_moneda',
    'cdo_bieser',
    'cdo_anados',
    'ple_estado',
    'cuo_modifi',
    'cdo_presup',
    'cdo_flucaj',
    'cdo_anauno',
  ].freeze

  GLOSA_AFP = {
    'AFP APORTE' => 'FONDO AFP',
    'AFP PRIMA DE SEGUROS' => 'SEGURO AFP',
    'AFP SEGURO' => 'SEGURO AFP',
    'AFP COMISIÓN' => 'COMISION AFP',
  }.freeze

  NO_CONTABILIZAR_INFORMATIVOS = [
    "provision_bonificacion_extraordinaria_gratificacion_deber",
    "provision_bonificacion_extraordinaria_gratificacion_haber",
    "provision_cts_deber",
    "provision_cts_haber",
    "provision_gratificacion_haber",
    "provision_gratificacion_deber",
    "provision_vacaciones_haber",
    "provision_vacaciones_deber",
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    obj_contabilidad = descartar_informativos(obj_contabilidad)

    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    Exportador::BaseXlsx.autofit sheet, [CABECERA]
    Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA, 0)

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    date_month = I18n.l(date, format: '%m')
    date_year_month = I18n.l(date, format: '%Y%m')
    date_mmyyyy = I18n.l(date, format: '%b %Y')
    fecha_movimiento = empresa.custom_attrs["Fecha de Movimiento"]
    fecha_cod_referencia = empresa.custom_attrs["Fecha codigo de referencia"]
    tipo_cambio = empresa.custom_attrs["Tipo de Cambio Asiento"].to_f
    cod_usuario = empresa.custom_attrs["Codigo Usuario Asiento"]

    obj_contabilidad = obj_contabilidad.group_by do |l|
      {
        cuenta_contable: search_cuenta(l),
        lado: l.deber_o_haber,
        centro_costos: l.centro_costo,
        glosa: l.cuenta_custom_attrs["Glosa"],
        cod_referencia: l.cuenta_custom_attrs["cdo_refere"],
        cod_contable: l.employee_custom_attrs["Codigo Contable"],
        glosa_interna: l.cuenta_custom_attrs["Glosa interna"],
      }
    end

    data = obj_contabilidad.lazy.map do |k, v|
      monto = v.sum(&:monto)
      [
        fecha_movimiento,
        date_month,
        "P",
        k[:cuenta_contable],
        nil,
        k[:centro_costos],
        k[:cod_contable],
        "#{k[:cod_referencia]}#{fecha_cod_referencia}",
        nil,
        date_year_month,
        k[:lado] == 'D' ? monto : 0,
        k[:lado] == 'C' ? monto : 0,
        k[:lado] == 'D' && tipo_cambio != 0 ? monto / tipo_cambio : 0,
        k[:lado] == 'C' && tipo_cambio != 0 ? monto / tipo_cambio : 0,
        "#{k[:glosa]} #{date_mmyyyy.to_s.capitalize}",
        nil,
        cod_usuario,
        *Array.new(6),
        tipo_cambio,
        "S",
        "PEN",
        *Array.new(6),
        k[:glosa_interna],
      ]
    end

    Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 1, number_format: '#,##0.00'
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  private
    def search_cuenta(l)
      if l.cuenta_custom_attrs["AFP"].to_s.casecmp('si').zero?
        attr_afp = GLOSA_AFP[l.glosa.upcase].to_s
        afp_method(l)&.custom_attrs&.dig(attr_afp)
      else
        l.cuenta_contable
      end
    end

    def descartar_informativos(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_INFORMATIVOS.include?(l.nombre_cuenta)
      end
    end
end

# EXAMPLE 19
#ipesa.rb


# Archivo de Centralizacion Personalizada cliente Ipesa Perú
class Exportador::Contabilidad::Peru::Personalizadas::Ipesa < Exportador::Contabilidad
  def initialize
    super()
    @extension = 'xlsx'
  end
  def create_lineas_liquidacion(liquidacions, **args)
    ::Contabilidad::Peru::LineasLiquidacionesService.new(liquidacions, **args)
  end
  def generate_doc(_empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, "Centralización Contable"
    fecha = variable.end_date.strftime("%d.%m.%Y")
    mes = variable.end_date.strftime('%m')
    anio = variable.end_date.strftime('%Y')
    index = 0
    titulos = ['NEWKO',
               'NEWBS',
               'NEWUM',
               'WRBTR',
               'ZFBDT',
               'ZUONR',
               'VALUT',
               'SGTXT',
               'KOSTL',
               'MWSKZ',]
    agrupado = ["CENCO", "CONCEPTO"]
    group = obj_contabilidad.select{|o| agrupado.include?(o.cuenta_custom_attrs&.dig("Agrupador"))}.group_by do |o|
      {
        cuenta_contable: o.cuenta_contable,
        deber_o_haber: o.deber_o_haber,
        sgtxt: search_sgtxt(o, variable),
        mwskz: search_mwskz(o),
        concepto: I18n.transliterate(search_concepto(o)),
        cenco: I18n.transliterate(search_cenco(o)),
      }
    end
    group.map do |k, v|
      data = [
        k[:cuenta_contable],
        k[:deber_o_haber] == 'D' ? 40 : 50,
        nil,
        v.sum(&:monto),
        fecha,
        "Prov. Plla. Emple. #{mes}#{anio}",
        fecha,
        k[:sgtxt],
        k[:cenco],
        k[:mwskz],
      ]
      Exportador::BaseXlsx.escribir_celdas sheet, [data], offset: index + 1, number_format: "#,##0"
      index += 1
    end
    complemento = obj_contabilidad.reject{|o| agrupado.include?(o.cuenta_custom_attrs&.dig("Agrupador"))}
    complemento.each do |l|
      data = [
        l.cuenta_contable,
        l.deber_o_haber == "D" ? 40 : 50,
        nil,
        l.deber_o_haber == "D" ? l.deber : l.haber,
        fecha,
        "Prov. Plla. Emple. #{mes}#{anio}",
        fecha,
        search_sgtxt(l, variable),
        search_cenco(l),
        search_mwskz(l),
      ]
      Exportador::BaseXlsx.escribir_celdas sheet, [data], offset: index + 1, number_format: "#,##0"
      index += 1
    end
    Exportador::BaseXlsx.crear_encabezado(sheet, titulos, 0)
    Exportador::BaseXlsx.autofit sheet, [titulos]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end
  private
    def search_sgtxt object, variable
      mes = variable.end_date.strftime('%m')
      anio = variable.end_date.strftime('%Y')
      case object.cuenta_custom_attrs&.dig("SGTXT")
      when 'PERIODO'
        "Prov. Plla. Emple. #{mes}#{anio}"
      when 'ITEM'
        object.glosa
      when 'DNI'
        object.numero_documento
      end
    end
    def search_mwskz object
      if  object.deber_o_haber == "C"
        ""
      end || "CO"
    end
    def search_concepto object
      return object.glosa if object.cuenta_custom_attrs&.dig("Agrupador")&.upcase == "CONCEPTO"
      object.cuenta_custom_attrs&.dig("Nombre cuenta Contable")
    end
    def search_cenco object
      object.centro_costo if object.cuenta_custom_attrs&.dig("Agrupador")&.upcase != "CONCEPTO" && object.centro_costo.present? && object.deber_o_haber == "D"
    end
end

# EXAMPLE 20
#unidosporelobjetivo.rb


# frozen_string_literal: true

# Archivo de Centralizacion Personalizada cliente Unidosporelobjetivo
class Exportador::Contabilidad::Peru::Personalizadas::Unidosporelobjetivo < Exportador::Contabilidad::Peru::CentralizacionContable
  def initialize
    super()
    @extension = 'xlsx'
  end

  HEADER_1 = [
    "Origen",
    "Num.Voucher",
    "Fecha",
    "Cuenta",
    "Monto Debe",
    "Monto Haber",
    "Moneda S/D",
    "T.Cambio",
    "Doc",
    "Num.Doc",
    "Fec.Doc",
    "Fec.Ven",
    "Cod.Prov.Clie",
    "C.Costo",
    "Presupuesto",
    "F.Efectivo",
    "Glosa",
    "Libro C/V/R",
    "Mto.Neto 1",
    "Mto.Neto 2",
    "Mto.Neto 3",
    "Mto.Neto 4",
    "Mto.Neto 5",
    "Mto.Neto 6",
    "Mto.Neto 7",
    "Mto.Neto 8",
    "Mto.Neto 9",
    "Mto.IGV",
    "Ref.Doc",
    "Ref.Num.Doc",
    "Ref.Fecha",
    "Det.Num",
    "Det.Fecha",
    "RUC",
    "R.Social",
    "Tipo",
    "Tip.Doc.Iden",
    "Medio de Pago",
    "Apellido 1",
    "Apellido 2",
    "Nombre",
    "T.Bien",
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    Exportador::BaseXlsx.autofit sheet, [HEADER_1]
    Exportador::BaseXlsx.crear_encabezado(sheet, HEADER_1, 0)

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    fecha_completa = I18n.l(date, format: "%d/%m/%Y")
    mes = I18n.l(date, format: "%m")

    obj_contabilidad = obj_contabilidad.group_by do |l|
      {
        num_voucher: l.cuenta_custom_attrs["Num.Voucher"],
        cuenta_contable: search_account(l),
        deber_o_haber: l.deber_o_haber,
        num_doc: l.cuenta_custom_attrs["Num Doc"],
        centro_costo: search_cc(l),
        glosa: search_glosa(l),
        libro: l.cuenta_custom_attrs["Libro C/V/R"],
        tipo: l.cuenta_custom_attrs["Tipo"],
        tipo_documentto: l.cuenta_custom_attrs["Tip.Doc.Iden"],

      }
    end

    data = obj_contabilidad.map do |k, v|

      [
        "11",
        k[:num_voucher],
        fecha_completa,
        k[:cuenta_contable],
        k[:deber_o_haber] == "D" ? v.sum(&:monto) : nil,
        k[:deber_o_haber] == "C" ? v.sum(&:monto) : nil,
        "S",
        "1,00",
        "BS",
        mes,
        fecha_completa,
        fecha_completa,
        empresa.rut&.humanize,
        k[:centro_costo],
        nil,
        nil,
        k[:glosa],
        k[:libro],
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        empresa.rut&.humanize,
        "SISCONT.COM SAC",
        k[:tipo],
        k[:tipo_documentto],
      ]
    end
    Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 1, number_format: '###0.00'
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

end

# EXAMPLE 21
#astara.rb


# Clase para generar contabilidad personalizada de Astara Péru
class Exportador::Contabilidad::Peru::Personalizadas::Astara < Exportador::Contabilidad
  include ContabilidadPeruHelper
  require 'csv'
  TITULO_SPIGA =
    [
      'F. Asiento',
      'Tipo Asiento',
      'Concepto Asiento',
      'T. operacion',
      'Cuenta',
      'D/H',
      'Importe',
      'Entidad',
      'Tercero',
      'Cta Bancaria',
      'Centro',
      'Dpto',
      'Seccion',
      'Marca',
      'Concepto Bancario',
      'Moneda',
      'Factor Cambio',
    ].freeze
  TITULO_SAP = ["T", "BP06", "1"].freeze

  NO_CONTABILIZAR_INFORMATIVOS = [
    "buk_provision_vacaciones",
    "buk_provision_gratificacion",
    "buk_provision_cts",
    "buk_provision_bonificacion_gratificacion",
  ].freeze

  DATOS = ["Remuneraciones", "Provisiones"].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?
    obj_contabilidad = descartar_informativos(obj_contabilidad)

    #SPIGA
    group_detalle_spiga = obj_contabilidad.select{|o| o.cuenta_custom_attrs&.dig("Tipo Planilla") == "Remuneraciones"}.group_by do |l|
      agrupador_spiga(l)
    end
    group_provision_spiga = obj_contabilidad.select{|o| o.cuenta_custom_attrs&.dig("Tipo Planilla") == "Provisiones"}.group_by do |l|
      agrupador_spiga(l)
    end
    group_liquidacion_spiga = obj_contabilidad.select{|o| o.cuenta_custom_attrs&.dig("Tipo Planilla") == "Liquidaciones"}.group_by do |l|
      agrupador_spiga(l)
    end
    #SAP
    group_detalle_sap = obj_contabilidad.select{|o| o.cuenta_custom_attrs&.dig("Tipo Planilla") == "Remuneraciones"}
    group_provision_sap = obj_contabilidad.select{|o| o.cuenta_custom_attrs&.dig("Tipo Planilla") == "Provisiones"}
    group_liquidacion_sap = obj_contabilidad.select{|o| o.cuenta_custom_attrs&.dig("Tipo Planilla") == "Liquidaciones"}
    #generamos los archivos
    spiga_detalle = generate_csv_spiga(empresa, variable, group_detalle_spiga)
    spiga_provision = generate_csv_spiga(empresa, variable, group_provision_spiga)
    spiga_finiquito = generate_csv_spiga(empresa, variable, group_liquidacion_spiga)
    sap_detalle = generate_csv_sap(empresa, variable, group_detalle_sap)
    sap_provision = generate_csv_sap(empresa, variable, group_provision_sap)
    sap_finiquito = generate_csv_sap(empresa, variable, group_liquidacion_sap)
    if empresa.custom_attrs&.dig("Modelo Contable") == "SAP"
      {
        centra_det_sap: Exportador::Contabilidad::AccountingFile.new(contents: sap_detalle, extension: 'csv', name_formatter: -> (name) { "#{name}-centralizacion-rem-SAP"}),
        centra_prov_sap: Exportador::Contabilidad::AccountingFile.new(contents: sap_provision, extension: 'csv', name_formatter: -> (name) { "#{name}-Centralizacion-prov-SAP"}),
        centra_liq_sap: Exportador::Contabilidad::AccountingFile.new(contents: sap_finiquito, extension: 'csv', name_formatter: -> (name) { "#{name}-Centralizacion-liq-SAP"}),
      }
    else
      {
        centra_det_spiga: Exportador::Contabilidad::AccountingFile.new(contents: spiga_detalle, extension: 'csv', name_formatter: -> (name) { "#{name}-centralizacion-rem-SPIGA"}),
        centra_prov_spiga: Exportador::Contabilidad::AccountingFile.new(contents: spiga_provision, extension: 'csv', name_formatter: -> (name) { "#{name}-Centralizacion-prov-SPIGA"}),
        centra_liq_spiga: Exportador::Contabilidad::AccountingFile.new(contents: spiga_finiquito, extension: 'csv', name_formatter: -> (name) { "#{name}-Centralizacion-liq-SPIGA"}),
      }
    end
  end

  def generate_csv_spiga _empresa, variable, obj_contabilidad
    fecha = variable.end_date.strftime("%Y%m%d")
    mes = variable.end_date.strftime("%B")
    CSV.generate(col_sep: ";") do |csv|
      csv << TITULO_SPIGA
      obj_contabilidad.each do |k, v|
        csv << detalle_spiga(fecha, mes, k, v)
      end
    end
  end

  def generate_csv_sap _empresa, variable, obj_contabilidad
    fecha = variable.end_date.strftime("%Y%m%d")
    anno_mes = variable.end_date.strftime("%Y%m")
    groups = ["CENCOS", "TOTAL", "DNI", "TERCERO"]
    filtro_detalle = obj_contabilidad.reject{|lc| groups.include?(lc.cuenta_custom_attrs&.dig("Agrupacion SAP"))}
    agrupador = obj_contabilidad.select{|lc| groups.include?(lc.cuenta_custom_attrs&.dig("Agrupacion SAP"))}.group_by do |l|
      agrupador_sap(l)
    end
    CSV.generate(col_sep: "|") do |csv|
      csv << TITULO_SAP
      csv << complemento(fecha, anno_mes)
      filtro_detalle.each do |l|
        csv << print_detalle_sap(l, anno_mes)
      end
      agrupador.each do |k, v|
        csv << print_agrupador_sap(k, v, anno_mes)
      end
    end
  end

  def generate_data(empresa, variable, obj_contabilidad, **_args)
    return [] unless obj_contabilidad.present? && empresa.custom_attrs['Activar API'].to_s.parameterize == 'si'
    obj_contabilidad = descartar_informativos(obj_contabilidad)

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    fecha = date.strftime('%Y%m%d')
    mes_anno = date.strftime('%Y%m')
    value_date = date.strftime('%d%m%Y').first(8)
    data = []

    agrupador = obj_contabilidad.select{|o| DATOS.include?(o.cuenta_custom_attrs&.dig("Tipo Planilla"))}.group_by do |l|
      {
        clave_contabilizacion: clave_contabilizacion(l, empresa),
        cuenta_contable: search_cuenta_sap(l, empresa).to_s,
        cme: codigo_cme(l, empresa),
        glosa: search_glosa_sap(l),
        centro_costo: search_cenco_sap(l, empresa),
        centro_beneficio: search_centro_beneficio(l, empresa),
        debit_or_credit: l.deber_o_haber,
      }
    end

    agrupador.map do |k, v|
      data << [data_api(k, v, mes_anno, fecha, value_date)]
    end

    data
  end

  private

    def data_api k, v, mes_anno, fecha, value_date
      {
        constant: "P",
        mes_anno: mes_anno,
        lave_contabilizacion: k[:clave_contabilizacion],
        cuenta_contable: k[:cuenta_contable],
        cme: k[:cme],
        monto: v.sum(&:monto).to_s,
        constant2: "K030",
        fecha: fecha,
        glosa: k[:glosa],
        centro_costo: k[:centro_costo],
        centro_beneficio: k[:centro_beneficio],
        position_id: "P",
        position_key: k[:debit_or_credit] == "D" ? "40" : "50",
        gl_account: k[:cuenta_contable],
        value_date: value_date,
        amount: v.sum(&:monto),
        position_text: k[:glosa],
        cost_center: k[:centro_costo],
        profit_center: nil,
        trading_partner: nil,
        assignment: nil,
      }
    end

    def agrupador_spiga l
      if l.cuenta_custom_attrs&.dig("Agrupacion SPIGA") == "TOTAL"
        {
          deber_o_haber: l.deber_o_haber,
          cuenta: search_account_spiga(l),
        }
      else
        {
          deber_o_haber: l.deber_o_haber,
          search_tercero: l.cuenta_custom_attrs&.dig("Agrupacion SPIGA") == "TERCERO" ? l.employee_custom_attrs&.dig("Codigo de  Tercero") : nil, #Tercero
          idcenco: l.centro_costo_custom_attrs&.dig("IDCENCO"),
          dptp: l.centro_costo_custom_attrs&.dig("Dpto"),
          seccion: l.centro_costo_custom_attrs&.dig("Sección"),
          cuenta: search_account_spiga(l),
        }
      end
    end

    def detalle_spiga fecha, mes, k, v
      [
        fecha, #F. Asiento
        "NO", #Tipo Asiento
        "PLANILLA #{mes}", #Concepto Asiento
        "4", #T. operacion
        k[:cuenta], #Cuenta
        k[:deber_o_haber] == "D" ? "D" : "H", #D/H
        v.sum(&:monto), #Importe
        nil, #Entidad
        k[:search_tercero],
        nil, #Cta Bancaria
        k[:idcenco], #Centro
        k[:dptp], #Dpto
        k[:seccion], #Seccion
        nil, #Marca
        nil, #Concepto Bancario
        nil, #Moneda
        nil, #Factor Cambio
      ]
    end

    def agrupador_sap l
      {
        cuenta_contable: search_account_sap(l),
        deber_o_haber: l.deber_o_haber,
        tipo_doc: l.tipo_doc,
        ttype: l.cuenta_custom_attrs&.dig('TTYPE'),
        glosa: get_glosa_afp(l),
        centro_costo: search_cenco(l),
      }
    end
    def complemento fecha, anno_mes
      [
        'C',
        fecha,
        fecha,
        'IN',
        'BP06',
        'PEN',
        nil,
        anno_mes,
        anno_mes,
        nil,
        nil,
        nil,
      ]
    end
    def search_account_sap object
      return afp_method(object)&.numero if object.cuenta_custom_attrs["AFP"].to_s.casecmp("si").zero?
      agrupador = object.cuenta_custom_attrs["Agrupacion SAP"]
      if agrupador == "DNI"
        object.numero_documento
      elsif agrupador == "TERCERO"
        codigo_tercero = object.cuenta_custom_attrs["Código de tercero"]
        codigo_tercero.presence || object.employee_custom_attrs["Codigo de Tercero"]
      elsif agrupador == "CLIENTE"
        codigo_cliente = object.cuenta_custom_attrs["Código de cliente"]
        codigo_cliente.presence || object.job_custom_attrs["Codigo de cliente"]
      else
        object.cuenta_custom_attrs["SAP"]
      end
    end

    def get_glosa_afp object
      object.cuenta_custom_attrs["AFP"].to_s.casecmp("si").zero? ? get_afp(object) : object.glosa
    end

    def search_account_spiga object
      if object.nombre_cuenta == "afp"
        afp_method_spiga(object)
      else
        object.cuenta_custom_attrs&.dig("SPIGA")
      end
    end

    def search_cenco object
      object.centro_costo if object.cuenta_custom_attrs&.dig("Agrupacion SAP") == "CENCOS"
    end

    def afp_method_spiga object
      case object.afp&.upcase
      when "AFP HABITAT"
        afp_habitat
      when "AFP INTEGRA"
        afp_integra
      when "PRIMA AFP"
        prima_afp
      when "PROFUTURO AFP"
        profuturo_afp
      end&.custom_attrs&.dig("SPIGA")
    end

    def print_detalle_sap l, anno_mes
      [
        "P", #CODIGO
        anno_mes, #PostingKey
        l.tipo_doc, #AccountNumber
        search_account_sap(l), #SGLIndicator
        l.cuenta_custom_attrs&.dig('TTYPE'), #TransactionType
        l.monto, #Amount
        nil, #TaxAmount
        nil, #TaxCode
        nil, #TermsOfPaymentKey
        nil, #BaselineDate
        nil, #PaymentBlockKey
        nil, #Assignment
        I18n.transliterate(get_glosa_afp(l)), #Text
        nil, #InternalOrder
        l.centro_costo, #CostCenter
        nil, #ProfitCenter
        nil, #AlternativePayeeName
        nil, #Street
        nil, #District
        nil, #City
        nil, #TaxNumber
        nil, #CommercialActivity
        nil, #Telephone
        nil, #TaxAllow
        nil, #WBSElement
        nil, #Elemento PEP
      ]
    end

    def print_agrupador_sap k, v, anno_mes
      [
        "P", #CODIGO
        anno_mes, #PostingKey
        k[:tipo_doc], #AccountNumber
        k[:cuenta_contable], #SGLIndicator
        k[:ttype], #TransactionType
        v.sum(&:monto), #Amount
        nil, #TaxAmount
        nil, #TaxCode
        nil, #TermsOfPaymentKey
        nil, #BaselineDate
        nil, #PaymentBlockKey
        nil, #Assignment
        I18n.transliterate(k[:glosa]), #Text
        nil, #InternalOrder
        k[:centro_costo], #CostCenter
        nil, #ProfitCenter
        nil, #AlternativePayeeName
        nil, #Street
        nil, #District
        nil, #City
        nil, #TaxNumber
        nil, #CommercialActivity
        nil, #Telephone
        nil, #TaxAllow
        nil, #WBSElement
        nil, #Elemento PEP
      ]
    end

    def afp_habitat
      @afp_habitat ||= CuentaContable.cuentas_contables[:item]["afp habitat"]
    end

    def afp_integra
      @afp_integra ||= CuentaContable.cuentas_contables[:item]["afp integra"]
    end

    def prima_afp
      @prima_afp ||= CuentaContable.cuentas_contables[:item]["prima afp"]
    end

    def profuturo_afp
      @profuturo_afp ||= CuentaContable.cuentas_contables[:item]["profuturo afp"]
    end

    def clave_contabilizacion obj, empresa
      clave_personalizada = obj.cuenta_custom_attrs&.dig("Clave contabilidad #{empresa.nombre}")
      clave_personalizada.presence || obj.cuenta_custom_attrs["lave Contabilizacion"]
    end

    def search_cuenta_sap obj, empresa
      return afp_method(obj)&.numero if obj.cuenta_custom_attrs["AFP"].to_s.casecmp("si").zero?
      obj.cuenta_custom_attrs&.dig("Cod. Acreedor #{empresa.nombre}").presence || obj.cuenta_custom_attrs&.dig("SAP").presence || obj.cuenta_contable
    end

    def codigo_cme obj, empresa
      cme_personalizado = obj.cuenta_custom_attrs&.dig("CODIGO CME #{empresa.nombre}")
      cme_personalizado.presence || obj.cuenta_custom_attrs&.dig("Indicador CME")
    end

    def search_glosa_sap obj
      return get_afp(obj) if obj.cuenta_custom_attrs["AFP"].to_s.casecmp("si").zero?
      obj.cuenta_custom_attrs&.dig("Glosa SAP").presence || obj.glosa
    end

    def get_afp(obj)
      case obj.glosa
      when "Afp Comisión", "AFP Comisión"
        "Afp Comision #{afp_method_nombre(obj)}"
      when "Afp Prima De Seguros", "AFP Seguro"
        "Afp Prima De Seguros #{afp_method_nombre(obj)}"
      when "Afp Aporte", "AFP Aporte"
        "Afp Aporte #{afp_method_nombre(obj)}"
      end
    end

    def afp_method_nombre object
      case object.afp&.upcase
      when "AFP HABITAT"
        "Habitat"
      when "AFP INTEGRA"
        "Integra"
      when "PRIMA AFP"
        "Prima"
      when "PROFUTURO AFP"
        "Profuturo"
      end
    end

    def search_cenco_sap obj, empresa
      obj.cuenta_contable.to_s[0] == "6" ? search_cenco_reliq(obj, empresa).presence || obj.centro_costo : ""
    end

    def search_cenco_reliq obj, empresa
      if obj.employee.reliquidacions.present?
        empresa_cencos = {}
        Job.where(employee_id: obj.employee.id).each do |job|
          empresa_cencos[job.empresa.nombre] = job.cached_area.centro_costo
        end
        dato_cenco = empresa_cencos.map do |k, v|
          k.include?(empresa.nombre) ? v.to_s : nil
        end
        dato_cenco.compact[0]
      end
    end

    def search_centro_beneficio obj, empresa
      ["1", "2"].include?(obj.cuenta_contable.to_s[0]) ? search_cenco_reliq_beneficio(obj, empresa).presence || obj.centro_costo_custom_attrs&.dig("Centro de Beneficio").presence || "" : ""
    end

    def search_cenco_reliq_beneficio obj, empresa
      if obj.employee.reliquidacions.present?
        empresa_cencos = {}
        Job.where(employee_id: obj.employee.id).each do |job|
          empresa_cencos[job.empresa.nombre] = job.cached_area.centro_costo
        end
        dato_cenco = empresa_cencos.map do |k, v|
          k.include?(empresa.nombre) ? CentroCostoDefinition.find_by(code: v.to_s)&.custom_attrs&.dig("Centro de Beneficio") : nil
        end
        dato_cenco.compact[0]
      end
    end

    def descartar_informativos(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_INFORMATIVOS.include?(l.item_code)
      end
    end
end

# EXAMPLE 22
#grupo_patio.rb


# frozen_string_literal: true

#
# Estructura contable para generar centralizacion personalizada de cliente Grupo Patio 4
class Exportador::Contabilidad::Peru::Personalizadas::GrupoPatio < Exportador::Contabilidad::Peru::CentralizacionContable
  require 'csv'

  CABECERA_1_TXT = [
    "CSUBDIA",
    "CCOMPRO",
    "CFECCOM",
    "CCODMON",
    "CSITUA",
    "CTIPCAM",
    "CGLOSA",
    "CTOTAL",
    "CTIPO",
    "CFLAG",
    "CDATE",
    "CHORA",
    "CFECCAM",
    "CUSER",
    "CORIG",
    "CFORM",
    "CTIPCOM",
    "CEXTOR",
  ].freeze

  CABECERA_2_TXT = [
    "DSUBDIA",
    "DCOMPRO",
    "DSECUE",
    "DFECCOM",
    "DCUENTA",
    "DCODANE",
    "DCENCOS",
    "DCODMON",
    "DDH",
    "DIMPORT",
    "DTIPDOC",
    "DNUMDOC",
    "DFECDOC",
    "DFECVEN",
    "DAREA",
    "DFLAG",
    "DDATE",
    "DXGLOSA",
    "DUSIMPOR",
    "DMNIMPOR",
    "DCODARC",
    "DCODANE2",
    "DMEDPAG",
    "DTIPDOR",
    "DNUMDOR",
    "DFECDO2",
    "DIGVCOM",
    "DTIDREF",
    "DNDOREF",
    "DFECREF",
    "DMAQREF",
    "DBIMREF",
    "DIGVREF",
  ].freeze

  CABECERA_1_XLSX = [
    "Campo",
    "Sub Diario",
    "Número de Comprobante",
    "Fecha de Comprobante",
    "Código de Moneda",
    "Glosa Principal",
    "Tipo de Cambio",
    "Tipo de Conversión",
    "Flag de Conversión de Moneda",
    "Fecha Tipo de Cambio",
    "Cuenta Contable",
    "Código de Anexo",
    "Código de Centro de Costo",
    "Debe / Haber",
    "Importe Original",
    "Importe en Dólares",
    "Importe en Soles",
    "Tipo de Documento",
    "Número de Documento",
    "Fecha de Documento",
    "Fecha de Vencimiento",
    "Código de Area",
    "Glosa Detalle",
    "Código de Anexo Auxiliar",
    "Base Imponible Documento Referencia",
    "IGV Documento Provisión",
    "Tipo Referencia en estado MQ",
    "Número Serie Caja Registradora",
    "Fecha de Operación",
    "Tipo de Tasa",
    "Tasa Detracción/Percepción",
    "Importe Base Detracción/Percepción Dólares",
    "Importe Base Detracción/Percepción Soles",
    "Tipo Cambio para 'F'",
    "Importe de IGV sin derecho crédito fiscal",
  ].freeze

  CABECERA_2_XLSX = [
    "Restricciones",
    "Ver T.G. 02",
    "Los dos primeros dígitos son el mes y los otros 4 siguientes un correlativo",
    " ",
    "Ver T.G. 03",
    " ",
    "Llenar  solo si Tipo de Conversión es 'C'. Debe estar entre >=0 y <=9999.999999",
    "Solo: 'C'= Especial, 'M'=Compra, 'V'=Venta , 'F' De acuerdo a fecha",
    "Solo: 'S' = Si se convierte, 'N'= No se convierte",
    "Si  Tipo de Conversión 'F'",
    "Debe existir en el Plan de Cuentas",
    "Si Cuenta Contable tiene seleccionado Tipo de Anexo, debe existir en la tabla de Anexos",
    "Si Cuenta Contable tiene habilitado C. Costo, Ver T.G. 05",
    " 'D' ó 'H'",
    "Importe original de la cuenta contable. Obligatorio, debe estar entre >=0 y <=99999999999.99",
    "Importe de la Cuenta Contable en Dólares. Obligatorio si Flag de Conversión de Moneda esta en 'N', debe estar entre >=0 y <=99999999999.99",
    "Importe de la Cuenta Contable en Soles. Obligatorio si Flag de Conversión de Moneda esta en 'N', debe estra entre >=0 y <=99999999999.99",
    "Si Cuenta Contable tiene habilitado el Documento Referencia Ver T.G. 06",
    "Si Cuenta Contable tiene habilitado el Documento Referencia Incluye Serie y Número",
    "Si Cuenta Contable tiene habilitado el Documento Referencia",
    "Si Cuenta Contable tiene habilitada la Fecha de Vencimiento",
    "Si Cuenta Contable tiene habilitada el Area. Ver T.G. 26",
    " ",
    "Si Cuenta Contable tiene seleccionado Tipo de Anexo Referencia",
    "Si Tipo de Documento es 'NC', 'NA' ó 'ND'",
    "Si Tipo de Documento es 'NC', 'NA' ó 'ND'",
    "Si la Cuenta Contable tiene Habilitado Documento Referencia 2 y  Tipo de Documento es 'TK'",
    "Si la Cuenta Contable teien Habilitado Documento Referencia 2 y  Tipo de Documento es 'TK'",
    "Si la Cuenta Contable tiene Habilitado Documento Referencia 2. Cuando Tipo de Documento es 'TK', consignar la fecha de emision del ticket",
    "Si la Cuenta Contable tiene configurada la Tasa:  Si es '1' ver T.G. 28 y '2' ver T.G. 29",
    "Si la Cuenta Contable tiene conf. en Tasa:  Si es '1' ver T.G. 28 y '2' ver T.G. 29. Debe estar entre >=0 y <=999.99",
    "Si la Cuenta Contable tiene configurada la Tasa. Debe ser el importe total del documento y estar entre >=0 y <=99999999999.99",
    "Si la Cuenta Contable tiene configurada la Tasa. Debe ser el importe total del documento y estar entre >=0 y <=99999999999.99",
    "Especificar solo si Tipo Conversión es 'F'. Se permite 'M' Compra y 'V' Venta.",
    "Especificar solo para comprobantes de compras con IGV sin derecho de crédito Fiscal. Se detalle solo en la cuenta 42xxxx",
  ].freeze

  CABECERA_3_XLSX = [
    "Tamaño/Formato",
    "4 Caracteres",
    "6 Caracteres",
    "dd/mm/aaaa",
    "2 Caracteres",
    "40 Caracteres",
    "Numérico 11, 6",
    "1 Caracteres",
    "1 Caracteres",
    "dd/mm/aaaa",
    "12 Caracteres",
    "18 Caracteres",
    "6 Caracteres",
    " ",
    "Numérico 14,2",
    "Numérico 14,2",
    "Numérico 14,2",
    "2 Caracteres",
    "20 Caracteres",
    "dd/mm/aaaa",
    "dd/mm/aaaa",
    "3 Caracteres",
    "30 Caracteres",
    "18 Caracteres",
    "8 Caracteres",
    "2 Caracteres",
    "20 Caracteres",
    "dd/mm/aaaa",
    "20 Caracteres",
    "Numérico 14,2 ",
    "Numérico 14,2",
    "'MQ'",
    "15 caracteres",
    "dd/mm/aaaa",
    "5 Caracteres",
    "Numérico 14,2",
    "Numérico 14,2",
    "Numérico 14,2",
    "1 Caracter",
    "Numérico 14,2",
  ].freeze

  ASIENTO = {
    'NOMINA' => 'Planilla Remuneración',
    'PROV CTS' => 'Provisión CTS',
    'PROC GRAT' => 'Provisión Gratificación',
    'PROV VCS' => 'Provisión Vacaciones',
    'LBS' => 'Planilla Liquidación',
    'Sin Clasificar' => 'Sin Clasificar',
  }.freeze

  ENCABEZADO_4 = ["MONEDA : MN SOLES"].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    mes = date.strftime('%m')
    fecha = date.strftime('%y%m%d')
    mes_anio = I18n.l(date, format: '%b-%Y').upcase
    dia_mes_anio = date.strftime('%d/%m/%Y')
    mes_anio_format2 = date.strftime('%m/%Y')

    obj_contabilidad.select(&:haber?).each do |pa|
      pa.deber_o_haber = "H"
    end
    data = {}

    grouped = obj_contabilidad.group_by{|l| l.cuenta_custom_attrs['Proceso'] || 'Sin Clasificar'}

    grouped.each do |k, obj|
      cabecera_dbf, cuerpo_dbf, cuerpo_xlsx = get_centralizaciones(variable, empresa, obj, k, mes, fecha, mes_anio, mes_anio_format2, dia_mes_anio)
      generate_datos(cabecera_dbf, cuerpo_dbf, cuerpo_xlsx, k, data)
    end
    data
  end

  def generate_cabecera_txt(empresa, obj, tipo_asiento, mes, fecha, mes_anio)
    return unless obj.present?
    CSV.generate(col_sep: '') do |csv|
      csv << CABECERA_1_TXT
      obj.each do |l|
        csv << [
          empresa.custom_attrs["DSUBDIA #{tipo_asiento}"],
          "#{mes} #{empresa.custom_attrs["DCOMPRO #{tipo_asiento}"]}",
          fecha,
          "MN",
          "F",
          nil,
          "#{l.cuenta_custom_attrs["DXGLOSA"]} #{mes_anio}",
          "0.00",
          "V",
          "S",
        ]
      end
    end
  end

  def generate_centralizacion_txt(empresa, obj, tipo_asiento, mes, fecha, mes_anio, mes_anio_format2)
    return unless obj.present?
    agrupador = obj.group_by do |o|
      {
        cuenta_contable: o.cuenta_custom_attrs[empresa.nombre],
        dcodane: o.cuenta_custom_attrs["DCODANE"].to_s.casecmp("MES").zero? ? mes : nil,
        centro_costo: get_cenco(o),
        deber_o_haber: o.deber_o_haber,
        dtipodoc: get_dtipodoc(o),
        numdoc: o.cuenta_custom_attrs["DNUMDOC"].to_s.casecmp("MES").zero? ? mes_anio_format2 : nil,
        glosa: "#{o.cuenta_custom_attrs["DXGLOSA"]} #{mes_anio}",
      }
    end
    CSV.generate(col_sep: '') do |csv|
      csv << CABECERA_2_TXT
      agrupador.map.with_index(1) do |(k, v), index|
        csv << [
          empresa.custom_attrs["DSUBDIA #{tipo_asiento}"],
          "#{mes}#{empresa.custom_attrs["DCOMPRO #{tipo_asiento}"]}",
          index.to_s.rjust(4, "0"),
          fecha,
          k[:cuenta_contable],
          k[:dcodane],
          k[:centro_costo],
          "MN",
          k[:deber_o_haber],
          v.sum(&:monto),
          k[:dtipodoc],
          k[:numdoc],
          fecha,
          nil,
          nil,
          "S",
          nil,
          k[:glosa],
          "0.00",
          "0.00",
        ]
      end
    end
  end

  def generate_centralizacion_xlsx(variable, empresa, obj, tipo_asiento, mes, dia_mes_anio, mes_anio, mes_anio_format2)
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA_1_XLSX, 0)
    Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA_2_XLSX, 1)
    Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA_3_XLSX, 2)
    glosa_general = "#{mes}#{empresa.custom_attrs["DCOMPRO #{tipo_asiento}"]}"

    valor_dolar = kpi_dolar(variable.id, empresa.id) || 1

    obj.select(&:haber?).each do |l|
      l.deber_o_haber = "H"
    end

    agrupador = obj.group_by do |l|
      {
        dxglosa: "#{l.cuenta_custom_attrs["DXGLOSA"]} #{mes_anio}",
        cuenta_contable: l.cuenta_contable,
        dcodane: l.cuenta_custom_attrs["DCODANE"].to_s.casecmp("MES").zero? ? mes : nil,
        centro_costo: search_cc(l),
        deber_o_haber: l.deber_o_haber,
        dtipodoc: get_dtipodoc(l),
        numdoc: l.cuenta_custom_attrs["DNUMDOC"].to_s.casecmp("MES").zero? ? mes_anio_format2 : nil,
        glosa: l.cuenta_custom_attrs["Glosa Detalle"],
      }
    end

    excel_data = agrupador.map do |k, v|
      [
        nil,
        empresa.custom_attrs["DSUBDIA #{tipo_asiento}"],
        glosa_general,
        dia_mes_anio,
        "MN",
        k[:dxglosa],
        valor_dolar,
        "V",
        "S",
        dia_mes_anio,
        k[:cuenta_contable],
        k[:dcodane],
        k[:centro_costo],
        k[:deber_o_haber],
        v.sum(&:monto),
        (v.sum(&:monto) / valor_dolar),
        v.sum(&:monto),
        k[:dtipodoc],
        k[:numdoc],
        dia_mes_anio,
        nil,
        nil,
        k[:glosa],
      ]
    end

    Exportador::BaseXlsx.escribir_celdas sheet, excel_data, offset: 3, number_format: "###0.00"
    Exportador::BaseXlsx.autofit sheet, [CABECERA_3_XLSX]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  private

    def get_cenco obj
      obj.centro_costo_custom_attrs&.dig("CECO") if obj.cuenta_custom_attrs["Agrupador"] == "CENCO"
    end

    def get_dtipodoc obj
      return if obj.cuenta_custom_attrs["DTIPDOC"] == "-"
      obj.cuenta_custom_attrs["DTIPDOC"]
    end

    def get_centralizaciones variable, empresa, obj, k, mes, fecha, mes_anio, mes_anio_format2, dia_mes_anio
      libro_cabecera_dbf = generate_cabecera_txt(empresa, obj, k, mes, fecha, mes_anio)
      libro_cuerpo_dbf = generate_centralizacion_txt(empresa, obj, k, mes, fecha, mes_anio, mes_anio_format2)
      libro_cuerpo_xlsx = generate_centralizacion_xlsx(variable, empresa, obj, k, mes, dia_mes_anio, mes_anio, mes_anio_format2)
      [libro_cabecera_dbf, libro_cuerpo_dbf, libro_cuerpo_xlsx]
    end

    def generate_datos cabecera_dbf, cuerpo_dbf, cuerpo_xlsx, k, data
      data["Libro_cabecera_#{k}"] = Exportador::Contabilidad::AccountingFile.new(contents: cabecera_dbf, extension: 'dbf', name_formatter: -> (name) {"CABECERA #{ASIENTO[k]} #{name}"})
      data["Libro_cuerpo_#{k}"] = Exportador::Contabilidad::AccountingFile.new(contents: cuerpo_dbf, extension: 'dbf', name_formatter: -> (name) {"DETALLE #{ASIENTO[k]} #{name}"})
      data["Libro_xlsx_cuerpo_#{k}"] = Exportador::Contabilidad::AccountingFile.new(contents: cuerpo_xlsx, extension: 'xlsx', name_formatter: -> (name) {"DETALLE_XLSX #{ASIENTO[k]} #{name}"})
    end
end

# EXAMPLE 23
#contabilidad10pearl.rb


# frozen_string_literal: true

#
#Exportador de comprobante contable para Contabilidad10pearl
class Exportador::Contabilidad::Peru::Personalizadas::Contabilidad10pearl < Exportador::Contabilidad::Peru::CentralizacionContable
  def initialize
    super()
    @extension = 'xlsx'
  end

  TITULOS = [
    "CUENTA",
    "NOMBRE DE CUENTA",
    "DEBE",
    "HABER",
    "CONCEPTO",
    "CENTRO DE COSTO",
  ].freeze

  def generate_doc(_empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    obj_contabilidad_ordenado = obj_contabilidad.group_by{|l| l.division_name || "Sin clasificar"}

    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    obj_contabilidad_ordenado.each do |k, obj|
      concepto = k.upcase
      hoja_proceso = Exportador::BaseXlsx.crear_hoja book, concepto
      crear_encabezado(hoja_proceso)
      data_proceso = generate_centralizacion(variable, obj, concepto)
      escribir_celdas(hoja_proceso, data_proceso)
      autofit(hoja_proceso)
    end
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def generate_centralizacion(variable, obj_contabilidad, concepto)
    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type).strftime('%m%Y')

    agrupado = obj_contabilidad.group_by do |obj|
      {
        cuenta_contable: cuenta_contable(obj),
        nombre_cuenta: obj.cuenta_custom_attrs["Nombre de la cuenta"],
        deber_haber: obj.deber_o_haber,
        cenco: search_cc(obj),
        nombre_cenco: nombre_cenco(obj),
        tipo_doc: obj.tipo_doc,
      }
    end

    agrupado.lazy.map do |k, v|
      [
        k[:cuenta_contable],
        k[:nombre_cuenta],
        k[:deber_haber] == "D" ? v.sum(&:monto) : 0,
        k[:deber_haber] == "C" ? v.sum(&:monto) : 0,
        "#{k[:tipo_doc]} #{concepto} #{date}",
        k[:cenco],
        k[:nombre_cenco],
      ]
    end
  end

  private
    def crear_hoja book, nombre_hoja
      Exportador::BaseXlsx.crear_hoja book, nombre_hoja
    end

    def crear_encabezado hoja
      Exportador::BaseXlsx.crear_encabezado(hoja, TITULOS, 0)
    end

    def escribir_celdas hoja, data
      Exportador::BaseXlsx.escribir_celdas hoja, data, offset: 1
    end

    def autofit hoja
      Exportador::BaseXlsx.autofit hoja, [TITULOS]
    end

    def nombre_cenco obj
      obj.cuenta_custom_attrs["Agrupador"] == "CENCO" ? obj.centro_costo_custom_attrs["Nombre Centro de Costo"] : nil
    end

    def cuenta_contable obj
      obj.cuenta_custom_attrs[(obj.centro_costo_custom_attrs["Nombre Centro de Costo"]).to_s].presence || obj.cuenta_contable
    end
end

# EXAMPLE 24
#bvl.rb


# frozen_string_literal: true

#
# Clase para centralizacion de Bvl
class Exportador::Contabilidad::Peru::Personalizadas::Bvl < Exportador::Contabilidad::Peru::CentralizacionContable
  include ContabilidadPeruHelper
  require 'csv'
  def initialize
    super()
    @extension = 'txt'
  end
  ASIENTO = ['Asiento de Planilla', 'Provision CTS', 'Provision Gratificacion', 'Provision Vacaciones'].freeze

  NO_CONTABILIZAR_INFORMATIVOS = [
    "provision_bonificacion_extraordinaria_gratificacion_deber",
    "provision_bonificacion_extraordinaria_gratificacion_haber",
    "provision_vacaciones_deber",
    "provision_vacaciones_haber",
  ].freeze

  def generate_doc(_empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    obj_contabilidad_custom = descartar_informativos(obj_contabilidad)

    obj_planilla = obj_contabilidad_custom.select{|l| l.cuenta_custom_attrs&.dig('Tipo de Asiento') == 'Asiento de Planilla'}
    obj_provisiones_cts = obj_contabilidad_custom.select{|l| l.cuenta_custom_attrs&.dig('Tipo de Asiento') == 'Provision CTS'}
    obj_provisiones_gratificacion = obj_contabilidad_custom.select{|l| l.cuenta_custom_attrs&.dig('Tipo de Asiento') == 'Provision Gratificacion'}
    obj_provisiones_vacaciones = obj_contabilidad_custom.select{|l| l.cuenta_custom_attrs&.dig('Tipo de Asiento') == 'Provision Vacaciones'}

    obj_contabilidad_sin_tipo_de_asiento = obj_contabilidad_custom.reject do |o|
      ASIENTO.include?(o.cuenta_custom_attrs&.dig("Tipo de Asiento"))
    end

    archivos = {
      obj_planilla: Exportador::Contabilidad::AccountingFile.new(contents: obj_data(obj_planilla, variable), name_formatter: -> (name) { "#{name}- Asiento de Planilla" }),
      obj_cts: Exportador::Contabilidad::AccountingFile.new(contents: obj_data(obj_provisiones_cts, variable), name_formatter: -> (name) { "#{name}- Provision de cts" }),
      obj_gratificacion: Exportador::Contabilidad::AccountingFile.new(contents: obj_data(obj_provisiones_gratificacion, variable), name_formatter: -> (name) { "#{name}- Provision de Gratificacion" }),
      obj_vacaciones: Exportador::Contabilidad::AccountingFile.new(contents: obj_data(obj_provisiones_vacaciones, variable), name_formatter: -> (name) { "#{name}- Provision de Vacaciones" }),
    }

    if obj_contabilidad_sin_tipo_de_asiento.present?
      centralizacion_sin_tipo_de_asiento = obj_data(obj_contabilidad_sin_tipo_de_asiento, variable)
      archivos[:sin_asiento] = Exportador::Contabilidad::AccountingFile.new(contents: centralizacion_sin_tipo_de_asiento, name_formatter: -> (name) { "#{name}- Sin tipo de asiento" })
    end
    archivos
  end

  private
    def obj_data(obj_contabilidad, variable)
      variable_fecha = variable.end_date
      mes = variable_fecha.strftime('%m')
      anio = variable_fecha.strftime('%Y')
      fecha = variable_fecha.strftime("%d/%m/%Y")
      group = metodo_agrupar(obj_contabilidad, mes, anio)
      CSV.generate(col_sep: '|') do |csv|
        group.each do |k, v|
          print_agrupados(csv, k, v, anio, mes, fecha)
        end
      end
    end

    def metodo_agrupar obj_contabilidad, mes, anio
      obj_contabilidad.group_by do |o|
        {
          cuenta_contable: search_account(o),
          glosa: get_glosa(o, mes, anio),
          ruc: get_ruc(o),
          centro_costo: search_cenco(o),
          deber_o_haber: o.deber_o_haber == "D" ? "D" : "H",
          serie: search_serie(o, mes),
          glosa_movimiento: search_glosa_movimiento(o),
          tipo_de_anexo: o.cuenta_custom_attrs&.dig("Tipo de Anexo"),
        }
      end
    end

    def print_agrupados csv, k, v, anio, mes, fecha
      csv << [
        k[:cuenta_contable],
        "#{anio}#{mes}",
        "05",
        "0001",
        fecha,
        k[:tipo_de_anexo],
        k[:ruc],
        "VR",
        k[:serie],
        fecha,
        "MN",
        v.sum(&:monto),
        "VTA",
        fecha,
        nil,
        k[:glosa],
        k[:centro_costo],
        k[:glosa_movimiento],
        "0",
        k[:deber_o_haber],
        nil,
        nil,
      ]
    end

    def search_serie object, mes
      if object.cuenta_custom_attrs&.dig("Glosa")&.parameterize(separator: " ") == "provision planilla"
        "#{object.cuenta_custom_attrs&.dig('Serie')}#{mes}"
      else
        object.cuenta_custom_attrs&.dig('Serie')
      end
    end

    def search_glosa_movimiento object
      "#{object.cuenta_custom_attrs&.dig("Tipo de Documento")}#{object.cuenta_custom_attrs&.dig("Serie")}"
    end

    def search_account obj
      afp = obj.afp.upcase
      return obj.cuenta_custom_attrs&.dig(afp) if obj.nombre_cuenta.include?("afp")
      obj.cuenta_contable
    end

    def get_glosa l, mes, anio
      "#{l.cuenta_custom_attrs&.dig("Glosa")} #{mes}-#{anio}" unless l.cuenta_custom_attrs&.dig("Agrupador") == "TOTAL"
    end

    def get_ruc obj
      ruc = search_ruc(obj)
      obj.cuenta_custom_attrs&.dig("Agrupador") == "TOTAL" ? obj.cuenta_custom_attrs&.dig("RUC") : ruc
    end

    def descartar_informativos(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_INFORMATIVOS.include?(l.nombre_cuenta)
      end
    end
end

# EXAMPLE 25
#sm.rb


# frozen_string_literal: true

#
# clase para generar centralizacion contable personalizada para sm
class Exportador::Contabilidad::Peru::Personalizadas::Sm < Exportador::Contabilidad::Peru::CentralizacionContable
  def initialize
    super()
    @extension = 'xlsx'
  end

  CABECERA = [
    "Mesv",
    "O.",
    "Vou.",
    "Cuenta",
    "Nombre Cta",
    "Débito",
    "Crédito",
    "M.",
    "T/C",
    "Fecha",
    "Glosa",
    "CODIGO/R.U.C.",
    "Razon Social",
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []

    obj_contabilidad.group_by{|l| l.cuenta_custom_attrs&.dig('Tipo de Asiento').presence || 'Sin tipo asiento'}.each do |k, obj|
      sheet = Exportador::BaseXlsx.crear_hoja book, k
      Exportador::BaseXlsx.autofit sheet, [CABECERA]
      Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA, 0)
      generate_each_sheet(sheet, empresa, variable, obj, k)
    end
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def generate_each_sheet(sheet, empresa, variable, obj_contabilidad, nombre_asiento)
    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    mes_proceso = variable.start_date.strftime('%m')
    tipo_cambio = kpi_dolar(variable.id, empresa.id, 'tipo_de_cambio')
    date_ddmmyyyy = I18n.l(date, format: '%d/%m/%Y')
    glosa = "#{nombre_asiento} #{I18n.l(date, format: '%B')}".upcase

    obj_contabilidad = obj_contabilidad.group_by do |l|
      {
        o_code: l.cuenta_custom_attrs&.dig("O."),
        cta: cuenta_afp_por_attr(l),
        lado: l.deber_o_haber,
        empleado: search_empleado(l),
      }
    end

    data = obj_contabilidad.lazy.map do |k, v|
      [
        mes_proceso,
        k[:o_code],
        '1',
        k[:cta][:numero],
        k[:cta][:nombre],
        k[:lado] == 'D' ? v.sum(&:monto) : 0,
        k[:lado] == 'C' ? v.sum(&:monto) : 0,
        'S',
        tipo_cambio,
        date_ddmmyyyy,
        glosa,
        k[:empleado][:dni],
        k[:empleado][:nombre],
      ]
    end

    Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 1, number_format: '#,##0.00'
  end

  private

    def cuenta_afp_por_attr(l)
      if l.cuenta_custom_attrs&.dig("AFP").to_s.casecmp('si').zero?
        {
          numero: l.cuenta_custom_attrs&.dig(l.afp || ''),
          nombre: l.afp,
        }
      else
        {
          numero: l.cuenta_contable,
          nombre: l.cuenta_custom_attrs&.dig('Nombre CC'),
        }
      end
    end

    def search_empleado(l)
      return {} unless l.cuenta_custom_attrs&.dig('Agrupador Contable') == 'DETALLE'
      {
        dni: "E-#{l.numero_documento}",
        nombre: "#{l.last_name},#{l.second_last_name},#{l.first_name&.tr(' ', ',')}".upcase,
      }
    end
end

# EXAMPLE 26
#comexa.rb


# frozen_string_literal: true

#Clase para la centralizacion personaliza cliente Comexa Perú
class Exportador::Contabilidad::Peru::Personalizadas::Comexa < Exportador::Contabilidad
  include ContabilidadPeruHelper
  def initialize
    super
    @extension = "xlsx"
  end

  HEADERS = [
    'NUMERO DE DOCUMENTO',
    'APELLIDOS',
    'NOMBRES',
    'CARGO',
    'CUENTA CONTABLE',
    'Monto Debe',
    'Monto Haber',
    'CENTRO COSTOS',
    'DESCRIPCIÓN CONCEPTO',
    'fecha contable',
    'moneda',
    'tipo de documento',
    'numero de documento',
    'Glosa',
    'fecha registro',
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, "Centralizacion contable #{empresa.nombre}"
    Exportador::BaseXlsx.crear_encabezado(sheet, HEADERS, 0)

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    end_date = date.strftime("%d/%m/%Y")
    mes_annio = date.strftime("%m/%Y")
    month_year = I18n.l(date, format: '%B %Y').upcase
    fecha = Time.zone.now.strftime("%d/%m/%Y")

    agrupador = agrupador(obj_contabilidad, month_year)

    excel_data = agrupador.lazy.map do |k, v|
      [
        k[:nro_documento],
        k[:apellido],
        k[:nombre],
        k[:cargo],
        k[:cuenta_contable],
        k[:deber_o_haber] == "D" ? v.sum(&:monto) : nil,
        k[:deber_o_haber] == "C" ? v.sum(&:monto) : nil,
        k[:cencos],
        k[:glosa],
        end_date,
        "01",
        "PL",
        mes_annio,
        k[:tipo_asiento],
        fecha,
      ]
    end
    Exportador::BaseXlsx.escribir_celdas sheet, excel_data, offset: 1
    Exportador::BaseXlsx.autofit sheet, [HEADERS]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def generate_data(_empresa, variable, obj_contabilidad, **_args)
    return {} unless obj_contabilidad.present?

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    end_date = date.strftime("%d/%m/%Y")
    mes_annio = date.strftime("%m/%Y")
    month_year = I18n.l(date, format: '%B %Y').upcase
    fecha = Time.zone.now.strftime("%d/%m/%Y")

    agrupador = agrupador(obj_contabilidad, month_year)

    agrupador.lazy.map do |k, v|
      {
        numero_documento: k[:nro_documento],
        apellidos: k[:apellido],
        nombres: k[:nombre],
        cargo: k[:cargo],
        cuenta_contable: k[:cuenta_contable],
        monto_debe: k[:deber_o_haber] == "D" ? v.sum(&:monto) : nil,
        monto_haber: k[:deber_o_haber] == "C" ? v.sum(&:monto) : nil,
        centro_costos: k[:cencos],
        descripcion_concepto: k[:glosa],
        fecha_contable: end_date,
        moneda: "01",
        tipo_de_documento: "PL",
        numero_de_documento: mes_annio,
        glosa: k[:tipo_asiento],
        fecha_registro: fecha,
      }
    end
  end
  private

    def agrupador obj_contabilidad, month_year
      obj_contabilidad.group_by do |l|
        apellidos, nombre, cargo = get_data_employee(l)
        {
          nro_documento: search_numero_documento(l),
          apellido: apellidos,
          nombre: nombre,
          cargo: cargo,
          cuenta_contable: search_account(l),
          deber_o_haber: l.deber_o_haber,
          cencos: search_cc(l),
          glosa: get_descripcion(l),
          tipo_asiento: glosa_tipo_asiento(l, month_year),
        }
      end
    end
    def get_data_employee l
      l.cuenta_custom_attrs&.dig("Agrupador") == "DNI" ? ["#{l.last_name} #{l.second_last_name}", l.first_name, l.role_name] : [nil, nil, nil]
    end

    def glosa_tipo_asiento l, month_year
      "#{l.cuenta_custom_attrs&.dig("Tipo de asiento")} #{month_year}"
    end

    def get_descripcion l
      l.glosa unless l.cuenta_custom_attrs&.dig("Agrupador") == 'TOTAL'
    end
end

# EXAMPLE 27
#mpa.rb


# frozen_string_literal: true

# Archivo de Centralizacion Personalizada cliente MPA
class Exportador::Contabilidad::Peru::Personalizadas::Mpa < Exportador::Contabilidad::Peru::CentralizacionContable
  def initialize
    super()
    @extension = 'xlsx'
  end

  HEADER_1 = [
    "Orig",
    "Num.Voucher",
    "Fecha",
    "Cuenta",
    "Monto Debe",
    "Monto Haber",
    "Moneda S/D ",
    "T.Cambio",
    "Doc",
    "Num.Doc",
    "Fec.Doc",
    "Fec.Ven",
    "Cod.Prov.Clie",
    "C.Costo",
    "Presupuesto",
    "F.Efectivo",
    "Glosa",
    "Libro C/V/R",
    "Mto.Neto 1",
    "Mto.Neto 2",
    "Mto.Neto 3",
    "Mto.Neto 4",
    "Mto.Neto 5",
    "Mto.Neto 6",
    "Mto.Neto 7",
    "Mto.Neto 8",
    "Mto.Neto 9",
    "Mto.IGV",
    "Ref.Doc",
    "Ref.Num.Doc",
    "Ref.Fecha",
    "D.Numero",
    "D.Fecha",
    "RUC",
    "R.Social",
    "Tipo",
    "Tip.Doc.Iden",
    "Medio de Pago",
    "Apellido 1",
    "Apellido 2",
    "Nombre",
    "T.Bien",
  ].freeze

  def generate_doc(_empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    fecha_completa = date.strftime("%d/%m/%Y")
    mes_y_anio = date.strftime("%m-%Y")

    obj_contabilidad_grupo = obj_contabilidad.group_by{|l| l.cuenta_custom_attrs["Tipo de Asiento"].presence || "Sin Categoria"}

    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []

    obj_contabilidad_grupo.each do |k, v|
      generate_centralizacion(variable, book, k, v, fecha_completa, mes_y_anio)
    end
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def generate_centralizacion(variable, book, sheet_name, obj_contabilidad, fecha_completa, mes_y_anio)
    sheet = Exportador::BaseXlsx.crear_hoja book, sheet_name
    Exportador::BaseXlsx.crear_encabezado(sheet, HEADER_1, 0)

    agrupador = obj_contabilidad.group_by do |l|
      kpi = kpi_dolar(variable.id, l.employee.id, "tipo_de_cambio").presence || 1
      {
        num_voucher: l.cuenta_custom_attrs["Num.Voucher"],
        cuenta_contable: get_cuenta(l),
        deber_o_haber: l.deber_o_haber,
        conversor: l.cuenta_custom_attrs["Conversor"].to_s.parameterize == "si" ? "D" : "S",
        tipo_doc: l.cuenta_custom_attrs["Tipo Doc"],
        cod_cliente: get_codigo_cliente(l),
        centro_costo: search_cenco(l),
        glosa: search_glosa(l),
        r_social: get_razon_social(l),
        valor_kpi: kpi,
        rut: get_rut(l),
      }
    end

    data = agrupador.map do |k, v|
      [
        "33",
        k[:num_voucher],
        fecha_completa,
        k[:cuenta_contable],
        k[:deber_o_haber] == "D" ? v.sum(&:monto) / k[:valor_kpi] : nil,
        k[:deber_o_haber] == "C" ? v.sum(&:monto) / k[:valor_kpi] : nil,
        k[:conversor],
        k[:valor_kpi],
        k[:tipo_doc],
        mes_y_anio,
        fecha_completa,
        fecha_completa,
        k[:cod_cliente],
        k[:centro_costo],
        nil,
        nil,
        k[:glosa],
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        k[:cod_cliente],
        k[:r_social],
      ]
    end
    Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 1
    Exportador::BaseXlsx.formatear_columna(sheet, data, [7], "#.##0")
    Exportador::BaseXlsx.autofit sheet, [HEADER_1]
  end

  private
    def get_cuenta obj
      return afp_method(obj)&.custom_attrs&.dig("AFP").to_s if obj.glosa.downcase.include?("afp")
      obj.cuenta_contable
    end

    def kpi_dolar(variable_id, employee_id, tipo_de_cambio)
      @kpi_dolar ||= Hash.new do |h, employee_id_arg|
        conditions = {
          variable_id: variable_id,
          employee_id: employee_id_arg,
          kpis: { code: tipo_de_cambio},
        }
        h[employee_id_arg] = KPIDatum.joins(:kpi).where(conditions).single_or_nil!&.value
      end
      @kpi_dolar[employee_id]
    end

    def get_codigo_cliente obj
      cod_prov = obj.cuenta_custom_attrs["Codigo Prov"].to_s
      return obj.numero_documento.to_s if cod_prov.casecmp("dni").zero?
      cod_prov
    end

    def get_razon_social obj
      r_social = obj.cuenta_custom_attrs["R. Social"].to_s
      return obj.employee.nombre_completo if r_social.casecmp("nombre completo").zero?
      r_social
    end

    def get_rut obj
      obj.numero_documento if obj.cuenta_custom_attrs["Agrupador Centro de Costo"].to_s.casecmp("no").zero?
    end
end

# EXAMPLE 28
#telecom_business_solution.rb


# frozen_string_literal: true

#
# Estructura contable para generar centralizacion personalizada de cliente SupraNetwork
class Exportador::Contabilidad::Peru::Personalizadas::TelecomBusinessSolution < Exportador::Contabilidad::Peru::CentralizacionContable
  require 'csv'

  def initialize
    super()
    @extension = 'csv'
  end

  CABECERA = [
    "External ID",
    "Currency",
    "Exchange Rate",
    "Date",
    "Accounting Period",
    "Ledger Account",
    "Debit",
    "Credit",
    "Note",
    "Nota 2",
    "Nombre",
    "Departamento",
    "Proyecto asignado",
  ].freeze

  NO_CONTABILIZAR_INFORMATIVOS = [
    "buk_provision_vacaciones",
    "buk_provision_gratificacion",
    "buk_provision_cts",
    "buk_provision_bonificacion_gratificacion",
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    obj_contabilidad = descartar_informativos(obj_contabilidad)

    obj_agrupado = obj_contabilidad.group_by{|l| l.cuenta_custom_attrs["Tipo de asiento"].presence || "Sin Tipo Asiento"}
    libros = {}

    obj_agrupado.each.with_index(empresa.custom_attrs["External ID"].to_i) do |(k, group), index|
      data = generate_archivo(variable, group, k, index)
      libros["Libro_#{k}".to_sym] = Exportador::Contabilidad::AccountingFile.new(contents: data, name_formatter: -> (name) {"#{name} - Centralizacion Contable #{k}"})
    end
    libros
  end

  private
    def generate_archivo(variable, obj_contabilidad, tipo_asiento, index)
      return unless obj_contabilidad.present?

      date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
      last_date = date.strftime("%d/%m/%Y")
      mes_str = I18n.l(date, format: '%B %Y').upcase
      month_year = I18n.l(date, format: '%b %Y').upcase

      agrupado = obj_contabilidad.group_by(&:numero_documento)
      CSV.generate(col_sep: ';') do |csv|
        csv << CABECERA
        agrupado.each do |_k, group| # rubocop:todo Style/HashEachMethods
          group.each do |l|
            nota_1, nota_2 = get_nota(l, tipo_asiento, mes_str)
            csv << [
              index,
              "SOL",
              "1",
              last_date,
              month_year,
              get_account(l),
              l.deber.presence || 0,
              l.haber.presence || 0,
              nota_1,
              nota_2,
              I18n.transliterate(l.employee.apellidos_nombre.to_s.delete(',').upcase),
              l.employee_custom_attrs&.dig("Departamento"),
              I18n.transliterate(get_cencos(l)),
            ]
          end
        end
      end
    end

    def get_nota obj, tipo_asiento, mes
      tipo_planilla = obj.employee_custom_attrs&.dig("Nota 2")
      case tipo_asiento
      when "LIQ BBS"
        ["#{tipo_asiento} #{obj.first_name} #{obj.last_name}", "#{tipo_planilla} #{obj.first_name} #{obj.last_name}"]
      when "ASIENTO DE PLANILLA", "PROVISION CTS", "PROVISION VACACIONES", "PROVISION GRATIFICACIONES"
        ["#{tipo_asiento} #{mes}", "#{tipo_planilla} #{mes}"]
      end
    end

    def get_account l
      l.cuenta_custom_attrs["AFP"] == "Sí" ? afp_method(l)&.numero : get_cuenta_by_plan_contable_dinamico(l, "employee")
    end

    def get_cencos l
      l.centro_costo.to_s == "0" ? nil : l.centro_costo
    end

    def descartar_informativos(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_INFORMATIVOS.include?(l.item_code)
      end
    end
end

# EXAMPLE 29
#finanty.rb


# frozen_string_literal: true

#
#Clase contable: Finanty
class Exportador::Contabilidad::Peru::Personalizadas::Finanty < Exportador::Contabilidad
  include ContabilidadPeruHelper
  def initialize
    super()
    @extension = 'xlsx'
  end

  TITULOS = [
    "Ejercicio",
    "Periodo",
    "Numero Cuenta",
    "Numero Serie",
    "Numero Documento",
    "Glosa",
    "Codigo Centro Costo",
    "Monto Debe",
    "Monto Haber",
  ].freeze

  CABECERA_IMPACTA = [
    "Correlativo",
    "Relacionado",
    "Codigo Tipo Medio Pago",
    "Ejercicio",
    "Periodo",
    "Cod_MR",
    "Modulo",
    "Fuente",
    "Numero Cuenta",
    "Codigo Tipo Document",
    "Numero Serie",
    "Numero Documento",
    "Glosa",
    "Codigo Moneda Origen",
    "Codigo Moneda Registro",
    "Codigo Centro Costo",
    "Codigo Sub Centro Costo",
    "Codigo Sub Sub Centro Costo",
    "Codigo Forma Prov",
    "Codigo Forma Pago/Cobro",
    "Codigo Area",
    "Identificador Ctr Mda",
    "Identificador Tip Afecto",
    "Nro Cheque",
    "Grdo",
    "Doc Ref Fecha Emision",
    "Doc Ref Cod Tip Doc",
    "Doc Ref Nro Serie",
    "Doc Ref Nro Doc",
    "CA01",
    "CA02",
    "CA03",
    "CA04",
    "CA05",
    "CA07",
    "CA07",
    "CA08",
    "CA09",
    "CA10",
    "CA11",
    "CA12",
    "CA13",
    "CA14",
    "CA15",
    "Cod Tip Doc Ident Clt",
    "Nro Doc Clt",
    "Razón Social 1",
    "Cod Tip Doc Ident Prov",
    "Nro Doc Prov",
    "Razón Social 2",
    "Cod Tip Doc Ident Trab",
    "Nro Doc Trab",
    "Razón Social 3",
    "Fecha Emision Doc",
    "Fecha Vencimiento Doc",
    "Fecha Movimiento",
    "Fecha Cbr",
    "Fecha Registro",
    "Fecha Conc",
    "Fecha Dif",
    "Monto Debe",
    "Monto Haber",
    "Monto Debe ME",
    "Monto Haber ME",
    "Cambio Moneda",
    "¿Es Cancelado?",
    "¿Es Conciliado?",
    "¿Es Provision?",
    "¿Es Anulado?",
    "¿Es Destino?",
  ].freeze

  CUENTAS_AFP = ['afp', 'buk_finiquito_aporte_afp', 'buk_finiquito_comision_afp', 'buk_finiquito_seguro_afp'].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    tipo_contabilidad = empresa.custom_attrs&.dig('Tipo de contabilidad')
    case tipo_contabilidad
    when "Modelo Finanty"
      generate_doc_finanty(empresa, variable, obj_contabilidad)
    else
      generate_doc_impacta(empresa, variable, obj_contabilidad)
    end
  end

  def generate_doc_impacta(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    annio = date.strftime("%Y")
    mes = date.strftime("%m")
    fecha_relacionado_1 = date.strftime("20/%m/%Y")
    fecha_relacionado_2 = date.strftime("%d/%m/%Y")
    @valor_dolar = KPIDatum.joins(:kpi).find_by('kpis.code = ? and kpi_data.empresa_id = ?', 'tipo_de_cambio', empresa.id)&.decimal_value || 1
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, "Centralizacion"
    Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA_IMPACTA, 0)

    agrupado = obj_contabilidad.sort_by{|l| [l.cuenta_custom_attrs&.dig("Relacionado - Impacta") || '']}.group_by do |obj|
      {
        relacionado: obj.cuenta_custom_attrs&.dig("Relacionado - Impacta"),
        cuenta_contable: search_account_impacta(obj),
        tipo_provision: get_provision(obj),
        glosa: search_name_account_impacta(obj) || obj.glosa.upcase,
        cencos: search_cc(obj),
        ruc: search_ructercero(obj),
        fecha_relacionado: get_fecha_relacionado(obj, fecha_relacionado_1, fecha_relacionado_2),
        deber_o_haber: obj.deber_o_haber,
        metodo: codsubcentro_identificadorctr(obj),
      }
    end

    data = agrupado.map.with_index(1) do |(k, v), index|
      codsubcentro, identificadorctr = k[:metodo]
      [
        index.to_s,
        k[:relacionado],
        nil,
        annio.to_s,
        mes.to_s,
        "03",
        "CT",
        "LD",
        k[:cuenta_contable],
        "00",
        k[:tipo_provision],
        "#{mes}#{annio}",
        k[:glosa],
        "01",
        "01",
        k[:cencos],
        k[:cencos],
        codsubcentro,
        nil,
        nil,
        "000001",
        identificadorctr,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        k[:cuenta_contable]&.first == "4" ? "6" : nil,
        k[:ruc],
        nil,
        nil,
        nil,
        nil,
        k[:fecha_relacionado],
        k[:fecha_relacionado],
        k[:fecha_relacionado],
        k[:fecha_relacionado],
        k[:fecha_relacionado],
        k[:fecha_relacionado],
        k[:fecha_relacionado],
        k[:deber_o_haber] == "D" ? v.sum(&:monto) : 0,
        k[:deber_o_haber] == "C" ? v.sum(&:monto) : 0,
        k[:deber_o_haber] == "D" ? v.sum(&:monto) / @valor_dolar : 0,
        k[:deber_o_haber] == "C" ? v.sum(&:monto) / @valor_dolar : 0,
        @valor_dolar,
        nil,
        nil,
        k[:cuenta_contable]&.first == "4" ? "1" : nil,
        "0",
      ]
    end

    Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 1, number_format: "###"
    Exportador::BaseXlsx.formatear_columna(sheet, data, [60, 61, 62, 63, 64], "###0.00")
    Exportador::BaseXlsx.autofit sheet, [CABECERA_IMPACTA]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def generate_doc_finanty(_empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?
    mes = variable.end_date.strftime("%m")
    anio = variable.end_date.strftime("%Y")

    bbss = excel_data(variable, obj_contabilidad.select{|l| l.cuenta_custom_attrs&.dig("Provision") == 'BBSS'}, mes, anio)
    remuneraciones = excel_data(variable, obj_contabilidad.select{|l| l.cuenta_custom_attrs&.dig("Provision") == 'REMUNERACIONES'}, mes, anio)
    liquidaciones = excel_data(variable, obj_contabilidad.select{|l| l.cuenta_custom_attrs&.dig("Provision") == 'LIQUIDACIONES'}, mes, anio)

    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []

    sheet_remuneraciones = Exportador::BaseXlsx.crear_hoja book, "Remuneraciones"
    sheet_bbss = Exportador::BaseXlsx.crear_hoja book, "BBSS"
    sheet_liquidaciones = Exportador::BaseXlsx.crear_hoja book, "Liquidaciones"

    Exportador::BaseXlsx.crear_encabezado(sheet_remuneraciones, TITULOS, 0)
    Exportador::BaseXlsx.crear_encabezado(sheet_bbss, TITULOS, 0)
    Exportador::BaseXlsx.crear_encabezado(sheet_liquidaciones, TITULOS, 0)

    Exportador::BaseXlsx.autofit sheet_remuneraciones, [TITULOS]
    Exportador::BaseXlsx.autofit sheet_bbss, [TITULOS]
    Exportador::BaseXlsx.autofit sheet_liquidaciones, [TITULOS]

    Exportador::BaseXlsx.escribir_celdas sheet_remuneraciones, remuneraciones, number_format: '###0.00'
    Exportador::BaseXlsx.escribir_celdas sheet_bbss, bbss, number_format: '###0.00'
    Exportador::BaseXlsx.escribir_celdas sheet_liquidaciones, liquidaciones, number_format: '###0.00'
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def excel_data _variable, obj_contabilidad, mes, anio
    agrupacion = obj_contabilidad.sort_by(&:deber_o_haber).reverse.group_by do |l|
      {
        cuenta_contable: search_account(l),
        tipo_doc: l.tipo_doc.to_s.upcase,
        nombre_cuenta: search_name_account(l) || l.glosa.upcase,
        centro_costo: search_cenco(l),
        deber_o_haber: l.deber_o_haber,
        ruc: search_ruc(l),
      }
    end

    agrupacion.map do |k, v|
      [
        anio,
        mes,
        k[:cuenta_contable],
        "#{mes}#{anio}",
        k[:tipo_doc],
        k[:nombre_cuenta],
        k[:centro_costo],
        k[:deber_o_haber] == "D" ? v.sum(&:monto) : nil,
        k[:deber_o_haber] == "C" ? v.sum(&:monto) : nil,
      ]
    end
  end

  def generate_data(_empresa, variable, obj_contabilidad, **_args)
    return [] unless obj_contabilidad.present?
    mes = variable.end_date.strftime("%m")
    anio = variable.end_date.strftime("%Y")

    obj_agrupado = obj_contabilidad.reject{|l| l.employee_custom_attrs&.dig("Agrupador Contable").to_s == "Si"}.group_by do |obj|
      {
        cuenta_contable: search_account(obj),
        tipo_doc: obj.tipo_doc.to_s.upcase,
        nombre_cuenta: search_name_account(obj).to_s.upcase,
        centro_costo: search_cenco(obj),
        deber_o_haber: obj.deber_o_haber,
        ruc: search_ruc(obj),
      }
    end
    data_agrupado = obj_agrupado.lazy.map do |k, v|
      {
        ejercicio: anio,
        periodo: mes,
        numero_cuenta: k[:cuenta_contable],
        numero_serie: "#{mes}#{anio}",
        numero_documento: k[:tipo_doc],
        glosa: k[:nombre_cuenta],
        codigo_centro_costo: k[:centro_costo],
        monto_debe: k[:deber_o_haber] == "D" ? v.sum(&:monto) : nil,
        monto_haber: k[:deber_o_haber] == "C" ? v.sum(&:monto) : nil,
      }
    end

    data_detalle = obj_contabilidad.select{|l| l.employee_custom_attrs&.dig("Agrupador Contable").to_s == "Si"}.lazy.map do |l|
      {
        ejercicio: anio,
        periodo: mes,
        numero_cuenta: search_account(l),
        numero_serie: "#{mes}#{anio}",
        numero_documento: l.tipo_doc.to_s.upcase,
        glosa: l.cuenta_custom_attrs&.dig("Nombre de la cuenta").to_s.upcase,
        codigo_centro_costo: l.centro_costo,
        monto_debe: l.deber,
        monto_haber: l.haber,
      }
    end
    data_agrupado + data_detalle
  end

  private

    def get_fecha_relacionado(obj, fecha_relacionado_1, fecha_relacionado_2)
      relacionado = obj.cuenta_custom_attrs&.dig("Relacionado - Impacta")

      case relacionado
      when "1"
        fecha_relacionado_1
      when "5"
        obj.origin&.job&.end_date&.strftime("%d/%m/%Y")
      else
        fecha_relacionado_2
      end
    end

    def get_provision(obj)
      tipo_prov = obj.cuenta_custom_attrs&.dig("Provision")

      case tipo_prov
      when "BBSS"
        "PROV"
      when "LIQUIDACIONES"
        "LBSS"
      else
        "PLLA"
      end
    end

    def search_cenco(obj)
      return if obj.cuenta_custom_attrs&.dig("Agrupador") == "TOTAL"
      obj.centro_costo
    end

    def search_ruc(obj)
      obj.numero_documento if obj.cuenta_custom_attrs&.dig("Agrupador") == "EMPLEADO"
    end

    def search_name_account l
      CUENTAS_AFP.include?(l.nombre_cuenta) ? afp_method_name_account(l) : l.cuenta_custom_attrs&.dig("Nombre de la cuenta")
    end

    def search_name_account_impacta l
      return l.cuenta_custom_attrs&.dig("Nombre de la cuenta") unless CUENTAS_AFP.include?(l.nombre_cuenta)
      "afp".include?(l.nombre_cuenta) ? afp_method_name_account(l) : "#{afp_method_name_account(l)} #{get_provision(l)}"
    end

    def search_ructercero l
      CUENTAS_AFP.include?(l.nombre_cuenta) ? ruc_tercero_afp(l) : l.cuenta_custom_attrs&.dig("RUC TERCERO - AL DIA")
    end

    def ruc_tercero_afp l
      case l.afp&.upcase
      when "AFP HABITAT"
        afp_habitat
      when "AFP INTEGRA"
        afp_integra
      when "PRIMA AFP"
        prima_afp
      when "PROFUTURO AFP"
        profuturo_afp
      end&.custom_attrs&.dig("RUC TERCERO - AL DIA")
    end

    def search_account l
      CUENTAS_AFP.include?(l.nombre_cuenta) ? afp_method_account(l) : agrupador_por_centro_costos(l)
    end

    def search_account_impacta l
      CUENTAS_AFP.include?(l.nombre_cuenta) ? afp_method_account_impacta(l) : agrupador_por_centro_costos_impacta(l)
    end

    def afp_method_account_impacta l
      case l.afp&.upcase
      when "AFP HABITAT"
        afp_habitat
      when "AFP INTEGRA"
        afp_integra
      when "PRIMA AFP"
        prima_afp
      when "PROFUTURO AFP"
        profuturo_afp
      end&.custom_attrs&.dig('Cuenta Contable impacta')
    end

    def afp_method_account l
      case l.afp&.upcase
      when "AFP HABITAT"
        afp_habitat
      when "AFP INTEGRA"
        afp_integra
      when "PRIMA AFP"
        prima_afp
      when "PROFUTURO AFP"
        profuturo_afp
      end&.numero
    end

    def agrupador_por_centro_costos_impacta(obj)
      agrupador_cencos = obj.centro_costo_custom_attrs&.dig('Agrupador Centro de Costo')
      return obj.cuenta_custom_attrs&.dig('Cuenta Contable impacta') unless agrupador_cencos.present?
      case agrupador_cencos
      when 'Staff'
        obj.cuenta_custom_attrs&.dig('Cuenta Contable 94').presence
      when 'Canales AlDia'
        obj.cuenta_custom_attrs&.dig('Cuenta Contable 95').presence
      when 'Operaciones'
        obj.cuenta_custom_attrs&.dig('Cuenta Contable 91').presence
      end || obj.cuenta_custom_attrs&.dig('Cuenta Contable impacta')
    end

    def agrupador_por_centro_costos(obj)
      agrupador_cencos = obj.centro_costo_custom_attrs&.dig('Agrupador Centro de Costo')
      return obj.cuenta_contable unless agrupador_cencos.present?
      case agrupador_cencos
      when 'Staff'
        obj.cuenta_custom_attrs&.dig('Cuenta Contable 94').presence
      when 'Canales AlDia'
        obj.cuenta_custom_attrs&.dig('Cuenta Contable 95').presence
      when 'Operaciones'
        obj.cuenta_custom_attrs&.dig('Cuenta Contable 91').presence
      end || obj.cuenta_contable
    end

    def afp_habitat
      @afp_habitat ||= CuentaContable.cuentas_contables[:item]["afp habitat"]
    end

    def afp_integra
      @afp_integra ||= CuentaContable.cuentas_contables[:item]["afp integra"]
    end

    def prima_afp
      @prima_afp ||= CuentaContable.cuentas_contables[:item]["prima afp"]
    end

    def profuturo_afp
      @profuturo_afp ||= CuentaContable.cuentas_contables[:item]["profuturo afp"]
    end

    def afp_method_name_account l
      case l.afp&.upcase
      when "AFP HABITAT"
        afp_habitat
      when "AFP INTEGRA"
        afp_integra
      when "PRIMA AFP"
        prima_afp
      when "PROFUTURO AFP"
        profuturo_afp
      end&.nombre&.upcase
    end

    def codsubcentro_identificadorctr l
      codsubcentro = "07999"
      identificadorctr = "a"
      search_cc(l).present? ? [codsubcentro, identificadorctr] : [nil, nil]
    end
end

# EXAMPLE 30
#zest_capital.rb


#frozen_string_literal: true

#Centralización personalizada ZEST Capital Perú
class Exportador::Contabilidad::Peru::Personalizadas::ZestCapital < Exportador::Contabilidad
  include ContabilidadPeruHelper
  def initialize
    super
    @extension = "xls"
  end

  HEADERS = ['Sub Diario',
             'Número de Comprobante',
             'Fecha de Comprobante',
             'Código de Moneda',
             'Glosa Principal',
             'Tipo de Cambio',
             'Tipo de Conversión',
             'Flag de Conversión de Moneda',
             'Fecha Tipo de Cambio',
             'Cuenta Contable',
             'Código de Anexo',
             'Código de Centro de Costo',
             'Debe / Haber',
             'Importe Original',
             'Importe en Dólares',
             'Importe en Soles',
             'Tipo de Documento',
             'Número de Documento',
             'Fecha de Documento',
             'Fecha de Vencimiento',
             'Código de Area',
             'Glosa Detalle',
             'Código de Anexo Auxiliar',
             'Medio de Pago',
             'Tipo de Documento de Referencia',
             'Número de Documento Referencia',
             'Fecha Documento Referencia',
             'Nro Máq. Registradora Tipo Doc. Ref.',
             'Base Imponible Documento Referencia',
             'IGV Documento Provisión',
             'Tipo Referencia en estado MQ',
             'Número Serie Caja Registradora',
             'Fecha de Operación',
             'Tipo de Tasa',
             'Tasa Detracción/Percepción',
             'Importe Base Detracción/Percepción Dólares',
             'Importe Base Detracción/Percepción Soles',
             'Tipo Cambio para "F"',
             'Importe de IGV sin derecho crédito fiscal',].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?
    book = Exportador::Base.crear_libro
    sheet = book.create_worksheet name: empresa.nombre
    variable_fecha = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    fecha_separada = variable_fecha.strftime("%d/%m/%Y")
    fecha_junta = variable_fecha.strftime("%d%m%Y")
    mes_palabras = I18n.l(variable_fecha, format: "%B").upcase
    mes = variable_fecha.strftime("%m")
    sheet.row(0).concat(HEADERS)
    agrupador = obj_contabilidad.group_by do |obj|
      {
        cuenta_contable: obj.cuenta_contable,
        cod_anexo: search_ruc(obj),
        cenco: search_cenco(obj),
        deber_haber: get_deber_haber(obj),
        glosa: obj.glosa,
      }
    end
    agrupador.each_with_index do |(k, v), index|
      sheet.row(index + 1).push(
        "35",
        "#{mes}0001",
        fecha_separada,
        "MN",
        "PLANILLA DE SUELDOS #{mes_palabras}",
        nil,
        "V",
        "S",
        nil,
        k[:cuenta_contable],
        k[:cod_anexo],
        k[:cenco],
        k[:deber_haber],
        v.sum(&:monto),
        nil,
        v.sum(&:monto),
        "PL",
        fecha_junta,
        fecha_separada,
        nil,
        nil,
        k[:glosa],
        nil,
        nil,
        "NA",
      )
    end
    Exportador::Base.cerrar_libro(book).contenido
  end

  private
    def get_deber_haber(obj)
      return "H" unless obj.deber_o_haber == "D"
      "D"
    end
end

# EXAMPLE 31
#armaval.rb


# frozen_string_literal: true

# Clase para generar contabilidad personalizada de Armaval
class Exportador::Contabilidad::Peru::Personalizadas::Armaval < Exportador::Contabilidad::Peru::CentralizacionContable
  def initialize
    super()
    @extension = 'xlsx'
  end

  TITULOS = [
    'cuenta',
    'tipo anexo',
    'T.Identidad',
    'codigo anexo',
    'Nombre_anexo',
    'debe',
    'haber',
    'codigo c.costo',
    'Tipo de documento',
    'Serie',
    'Numero',
    'Fecha Emisión',
    'Fecha Venc.',
    'Moneda',
    'Tipo de cambio',
    'Glosa',
  ].freeze

  TITULOS2 = [
    'RecordKey',
    'Series',
    'Código trans.',
    'F. Contabilización',
    'F. Vencimiento',
    'F. Documento',
    'Comentarios',
    'Referencia 2',
  ].freeze

  NO_CONTABILIZAR_INFORMATIVOS = [
    'buk_provision_vacaciones',
    'buk_provision_bonificacion_gratificacion',
    'buk_provision_gratificacion',
    'buk_provision_cts',
  ].freeze

  PROVISIONES = [
    "Provisión de vacaciones",
    "Provisión de CTS",
    "Provisión de gratificación",
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?
    obj_contabilidad_custom = descartar_informativos(obj_contabilidad)
    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    date_yyyymmdd = I18n.l(date, format: '%Y%m%d')
    mes_anio_str = I18n.l(date, format: '%B %Y').upcase
    mes_anio = I18n.l(date, format: '%m-%Y')
    anio = I18n.l(date, format: '%Y')
    date_ddmmyyyy = I18n.l(date, format: '%d/%m/%Y')

    books = {}
    obj_contabilidad_custom.group_by{|l| l.cuenta_custom_attrs['Tipo de asiento'].presence || 'Otros'}.each do |k, obj|
      glosa, comentarios, referencia = get_glosa(k, mes_anio, mes_anio_str)

      book = generate_book(obj, anio, date_ddmmyyyy, glosa)
      books[k] = Exportador::Contabilidad::AccountingFile.new(contents: book, name_formatter: -> (_name) {"#{empresa.nombre} - Detalle - #{k}"})
      cabecera = generate_cabecera(obj, date_yyyymmdd, referencia, comentarios)
      books["Cabecera-#{k}"] = Exportador::Contabilidad::AccountingFile.new(contents: cabecera, name_formatter: -> (_name) {"#{empresa.nombre} - Cabecera - #{k}"})
    end
    books
  end

  def generate_book(obj_contabilidad_custom, anio, date_ddmmyyyy, glosa)
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, "Centralizacion"
    Exportador::BaseXlsx.crear_encabezado(sheet, TITULOS, 0)

    agrupador = obj_contabilidad_custom.group_by do |l|
      identidad, dni_ruc, afp_nombre = get_identidad(l)
      {
        tipo_anexo: l.cuenta_custom_attrs['Tipo anexo'],
        identidad: identidad,
        dni_ruc: dni_ruc,
        lado: l.deber_o_haber,
        centro_costo: l.centro_costo,
        afp_nombre: afp_nombre,
        cuenta_contable: get_afp_cuentas(l),
        glosa: glosa,
      }
    end

    excel_data = agrupador.lazy.map do |(k, v)|
      [
        k[:cuenta_contable],
        k[:tipo_anexo],
        k[:identidad],
        k[:dni_ruc],
        k[:afp_nombre],
        k[:lado] == 'D' ? v.sum(&:monto) : nil,
        k[:lado] == 'C' ? v.sum(&:monto) : nil,
        k[:centro_costo],
        "VR",
        anio,
        date_ddmmyyyy.tr("/", ""),
        date_ddmmyyyy,
        date_ddmmyyyy,
        "01-SOLES",
        "1.0000",
        k[:glosa],
      ]
    end
    Exportador::BaseXlsx.escribir_celdas sheet, excel_data, offset: 1, number_format:  '###.0'
    Exportador::BaseXlsx.autofit sheet, [TITULOS]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def generate_cabecera obj_contabilidad_custom, date_yyyymmdd, referencia, comentarios
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, "Cabecera"
    Exportador::BaseXlsx.autofit sheet, [TITULOS2]
    Exportador::BaseXlsx.crear_encabezado(sheet, TITULOS2, 0)
    obj_contabilidad_custom.each do |l|
      data_cabecera(l, date_yyyymmdd, referencia, comentarios, sheet)
    end
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def data_cabecera l, date_yyyymmdd, referencia, comentarios, sheet
    data = ["1", "10", l.cuenta_custom_attrs['Correlativo'], date_yyyymmdd, date_yyyymmdd, date_yyyymmdd, comentarios, referencia]
    Exportador::BaseXlsx.escribir_celdas sheet, [data], offset: 1, number_format:  '#.#0'
  end

  private
    def get_identidad l
      case l.cuenta_custom_attrs['Agrupador']
      when "RUC"
        ["6-RUC", cod_anexo(l, l.ruc_afp), nombre_anexo(l, l.afp.upcase)]
      when "DNI"
        ["1-DNI", cod_anexo(l, l.numero_documento.to_s), nombre_anexo(l, l.employee.nombre_completo.upcase)]
      else
        ["7-PASAPORTE", cod_anexo(l, l.numero_documento.to_s), nombre_anexo(l, l.employee.nombre_completo.upcase)]
      end
    end

    def get_glosa(nombre, fecha, mes_anio_str)
      if nombre == "Asiento de planilla"
        ["#{nombre.upcase} #{fecha}", "Provisión de planilla #{mes_anio_str}", "PLAN #{fecha}"]
      elsif PROVISIONES.include?(nombre)
        ["#{nombre.upcase} #{fecha}", "PROV #{mes_anio_str}", "PROV #{fecha}"]
      end
    end

    def get_afp_cuentas l
      l.cuenta_custom_attrs['AFP'].to_s.casecmp("si").zero? ? get_afp(l) : l.cuenta_contable
    end

    def get_afp(l)
      case l.glosa.upcase
      when "AFP COMISIÓN"
        afp_method(l)&.custom_attrs&.dig("afp comision")
      when "AFP PRIMA DE SEGUROS", "AFP SEGURO"
        afp_method(l)&.custom_attrs&.dig("afp seguro")
      when "AFP APORTE"
        afp_method(l)&.numero
      end
    end

    def descartar_informativos(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_INFORMATIVOS.include?(l.item_code)
      end
    end

    def cod_anexo obj, cod
      cod if obj.cuenta_custom_attrs["Código de anexo"].to_s.casecmp("si").zero?
    end

    def nombre_anexo obj, nombre
      nombre if obj.cuenta_custom_attrs["Nombre de anexo"].to_s.casecmp("si").zero?
    end
end

# EXAMPLE 32
#b_motors_sac.rb


# frozen_string_literal: true

# Clase para generar centralizacion de cliente B Motors Sac Perú
class Exportador::Contabilidad::Peru::Personalizadas::BMotorsSac < Exportador::Contabilidad
  include ContabilidadPeruHelper

  def initialize
    super()
    @extension = 'xlsx'
  end

  HEADER = [
    'Cuenta contable',
    'Centro de Costo',
    'Fecha',
    'Concepto',
    'Debe',
    'Haber',
    'Codigo Quiter',
    'Glosa',
  ].freeze

  NO_CONTABILIZAR_INFORMATIVOS = [
    "provision_bonificacion_extraordinaria_gratificacion_deber",
    "provision_bonificacion_extraordinaria_gratificacion_haber",
    "provision_cts_deber",
    "provision_cts_haber",
    "provision_gratificacion_haber",
    "provision_gratificacion_deber",
    "buk_vida_ley_deber",
    "buk_vida_ley_haber",
    "buk_vida_ley",
    "provision_vacaciones_haber",
    "provision_vacaciones_deber",
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    obj_contabilidad = descartar_informativos(obj_contabilidad)

    libros = {}
    obj_contabilidad_grupo = obj_contabilidad.group_by{|l| l.cuenta_custom_attrs&.dig('Tipo de Asiento') || "Sin Tipo de Asiento"}

    obj_contabilidad_grupo.each do |k, obj|
      libro = generate_doc_centralizacion(empresa, variable, obj)
      libros["Libro_#{k}".to_sym] = Exportador::Contabilidad::AccountingFile.new(contents: libro, name_formatter: -> (name) {"#{name} #{k.upcase}"})
    end
    libros
  end

  def generate_doc_centralizacion(empresa, variable, obj)
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    Exportador::BaseXlsx.crear_encabezado(sheet, HEADER, 0)

    fecha = Variable::Utils.end_of_period(variable.start_date, variable.period_type).strftime("%d/%m/%Y")

    agrupador = obj.group_by do |l|
      {
        account_cc: search_account_cc(l),
        cencos: search_cc(l),
        glosa: I18n.transliterate(search_glosa_afp(l)),
        deber_o_haber: l.deber_o_haber,
        codigo_quiter: codigo_quiter(l),
      }
    end

    data = agrupador.lazy.map do |k, v|
      [
        k[:account_cc],
        k[:cencos],
        fecha,
        k[:glosa],
        k[:deber_o_haber] == "D" ? format("%#.2f", v.sum(&:monto)) : 0,
        k[:deber_o_haber] == "C" ? format("%#.2f", v.sum(&:monto)) : 0,
        k[:codigo_quiter],
        k[:glosa],
      ]
    end
    Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 1, number_format: '###0.00'
    Exportador::BaseXlsx.autofit sheet, [HEADER]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  private
    def search_account_cc l
      attrs_cenco = l.centro_costo_custom_attrs&.dig("Cuenta contable CC")
      l.cuenta_custom_attrs["Agrupador"] == "CENCO" ? l.cuenta_custom_attrs[attrs_cenco].to_s : search_account(l)
    end

    def codigo_quiter l
      I18n.transliterate(l.employee_custom_attrs&.dig("CODIGO QUITER")) if l.cuenta_custom_attrs["Agrupador"] == "DNI"
    end

    def descartar_informativos(obj)
      obj.select do |l|
        interseccion = [l.item_code, l.nombre_cuenta] & NO_CONTABILIZAR_INFORMATIVOS
        interseccion.empty?
      end
    end
end

# EXAMPLE 33
#l_r_global_logistic.rb


# rubocop:disable Buk/FileNameClass
# frozen_string_literal: true

# Clase para generar contabilidad personalizad de L&R Global Logistics
class Exportador::Contabilidad::Peru::Personalizadas::LRGlobalLogistic < Exportador::Contabilidad
  def initialize
    super()
    @extension = 'xlsx'
  end

  CABECERAS = [
    "CUENTA",
    "NOMBRE",
    "CODIGO",
    "DEBE",
    "HABER",
  ].freeze

  def generate_doc(_empresa, _variable, obj_contabilidad)
    return unless obj_contabilidad.present?
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet_remu = Exportador::BaseXlsx.crear_hoja book, "Centralizacion Remuneracion"
    sheet_liq = Exportador::BaseXlsx.crear_hoja book, "Centralizacion Liquidacion"
    sheet_prov = Exportador::BaseXlsx.crear_hoja book, "Centralizacion Provision"
    obj_remuneraciones = obj_contabilidad.select {|linea| linea.cuenta_custom_attrs&.dig("Proceso") == "Remuneraciones"}
    obj_liquidaciones = obj_contabilidad.select {|linea| linea.cuenta_custom_attrs&.dig("Proceso") == "Liquidaciones"}
    obj_provisiones = obj_contabilidad.select {|linea| linea.cuenta_custom_attrs&.dig("Proceso") == "Provisiones"}
    generar_hoja(generate_data(obj_remuneraciones), sheet_remu)
    generar_hoja(generate_data(obj_liquidaciones), sheet_liq)
    generar_hoja(generate_data(obj_provisiones), sheet_prov)
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def generate_data(obj_contabilidad)
    total_deberes = obj_contabilidad.select(&:deber?).sum(&:monto)
    total_haberes = obj_contabilidad.select(&:haber?).sum(&:monto)
    agrupados = obj_contabilidad.group_by do |obj|
      {
        cuenta_contable: get_cuenta_contable(obj),
        nombre_cuenta: get_nombre_cuenta_contable(obj),
        deber_haber: obj.deber_o_haber,
        codigo_empleado: get_codigo_empleado(obj),
      }
    end
    excel_data = agrupados.map do |k, v|
      [
        k[:cuenta_contable],
        k[:nombre_cuenta],
        k[:codigo_empleado],
        k[:deber_haber] == "D" ? v.sum(&:monto) : 0,
        k[:deber_haber] == "C" ? v.sum(&:monto) : 0,
      ]
    end
    footer = [nil, nil, "TOTAL S/.", total_deberes, total_haberes]
    excel_data += [footer]
    excel_data
  end

  private
    def get_cuenta_contable(obj)
      cuenta_contable = obj.cuenta_contable
      if obj.nombre_cuenta == "afp"
        afp = obj.afp.to_s
        obj.cuenta_custom_attrs&.dig(afp)
      elsif cuenta_contable == "0"
        clasificacion_contable = obj.job_custom_attrs&.dig("Clasificación Contable").to_s
        obj.cuenta_custom_attrs&.dig(clasificacion_contable).to_s
      else
        cuenta_contable
      end
    end

    def get_nombre_cuenta_contable(obj)
      return obj.afp if obj.nombre_cuenta == "afp"
      return obj.glosa if obj.cuenta_custom_attrs&.dig("Agrupador") != "CLASIFICACION"
      clasificacion_contable = obj.job_custom_attrs&.dig("Clasificación Contable").to_s
      "#{obj.glosa} #{clasificacion_contable}"
    end

    def get_codigo_empleado(obj)
      "E#{obj.numero_documento}" if obj.cuenta_custom_attrs&.dig("Agrupador") == "EMPLEADO"
    end

    def generar_hoja(content, sheet)
      Exportador::BaseXlsx.crear_encabezado sheet, CABECERAS
      Exportador::BaseXlsx.escribir_celdas sheet, content, offset: 1, number_format: "###0.00"
      Exportador::BaseXlsx.autofit sheet, [CABECERAS]
    end
end
# rubocop:enable Buk/FileNameClass

# EXAMPLE 34
#oml_import.rb


# frozen_string_literal: true

#Exportador de comprobante contable para cliente Oml Import
class Exportador::Contabilidad::Peru::Personalizadas::OmlImport < Exportador::Contabilidad::Peru::CentralizacionContable
  include ContabilidadPeruHelper

  def initialize
    super()
    @extension = 'xlsx'
  end

  CABECERA = [
    'account_id',
    'debit',
    'credit',
    'currency_id',
    'amount_currency',
    'tc',
    'partner_id',
    'type_document_id',
    'nro_comp',
    'date_maturity',
    'name',
    'analytic_account_id',
    'tax_ids',
    'amount_tax',
  ].freeze

  def generate_doc(_empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []

    obj_contabilidad = obj_contabilidad.group_by{|l| l.cuenta_custom_attrs["Tipo de asiento"].presence || "Otros"}
    obj_contabilidad.each do |asiento, obj_conta|
      generate_sheet(book, variable, obj_conta, asiento)
    end

    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def generate_sheet book, variable, obj_contabilidad, asiento
    sheet = Exportador::BaseXlsx.crear_hoja book, asiento
    Exportador::BaseXlsx.autofit sheet, [CABECERA]
    Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA, 0)

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    mes_annio = date.strftime("%Y-%m")

    agrupador = obj_contabilidad.group_by do |l|
      tipo_doc, nombres = get_tipo_doc(l)
      {
        cuenta_contable: search_account(l),
        deber_haber: l.deber_o_haber,
        nombres: nombres,
        tipo_doc: tipo_doc,
        glosa: search_glosa_afp(l),
        centro_costo: search_cenco(l),
      }
    end

    excel_data = agrupador.lazy.map do |k, v|
      [
        k[:cuenta_contable],
        k[:deber_haber] == "D" ? v.sum(&:monto) : nil,
        k[:deber_haber] == "C" ? v.sum(&:monto) : nil,
        nil,
        nil,
        nil,
        k[:nombres],
        k[:tipo_doc],
        mes_annio,
        nil,
        k[:glosa],
        k[:centro_costo],
        nil,
        nil,
      ]
    end

    Exportador::BaseXlsx.escribir_celdas sheet, excel_data, offset: 1
    Exportador::BaseXlsx.autofit sheet, [CABECERA]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  private
    def get_tipo_doc obj
      agrupador = obj.cuenta_custom_attrs["Agrupador"]
      nombre_completo = obj.employee.apellidos_nombre.to_s.tr(",", "")
      case agrupador
      when "DNI"
        [obj.numero_documento, nombre_completo]
      when "TOTAL"
        [ruc_afp(obj).to_s, nil]
      end
    end

    def ruc_afp obj
      obj.cuenta_custom_attrs["RUC"].presence || afp_method(obj)&.custom_attrs&.dig("RUC")
    end
end

# EXAMPLE 35
#archean.rb


# frozen_string_literal: true

# Clase para generar centralizacion de cliente Archean Services
class Exportador::Contabilidad::Peru::Personalizadas::Archean < Exportador::Contabilidad::Peru::CentralizacionContable
  require 'csv'
  def initialize
    super()
    @extension = 'txt'
  end

  NO_CONTABILIZAR_INFORMATIVOS = [
    'provision_gratificacion_deber',
    'provision_gratificacion_haber',
    'provision_bonificacion_extraordinaria_gratificacion_deber',
    'provision_bonificacion_extraordinaria_gratificacion_haber',
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    obj_contabilidad = descartar_cuentas(obj_contabilidad)
    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    date_dd_mm_yyyy = I18n.l(date, format: "%d/%m/%Y")
    date_mm = I18n.l(date, format: "%m")
    date_yyyy = I18n.l(date, format: "%Y")
    date_yyyymm = I18n.l(date, format: "%Y%m")
    date_mmstr = I18n.l(date, format: '%B')
    name_file = "#{empresa.rut}rd#{date_yyyymm}"
    dolar = kpi_dolar(variable.id, empresa.id) || 1

    obj_contabilidad = obj_contabilidad.group_by{|l| l.cuenta_custom_attrs['Tipo de asiento']}

    obj_contabilidad.map do |k, v|
      txt_file = generate_txt(v, date_dd_mm_yyyy, date_mm, date_yyyy, date_yyyymm, date_mmstr, dolar)
      ["file_#{k}", Exportador::Contabilidad::AccountingFile.new(contents: txt_file, name_formatter: -> (name) {k.present? ? "#{name_file}_#{k}" : name})]
    end.to_h
  end
  private

    def generate_txt(obj_contabilidad, date_dd_mm_yyyy, date_mm, date_yyyy, date_yyyymm, date_mmstr, dolar)
      obj_conta_agrupado = group_data(obj_contabilidad, date_dd_mm_yyyy, date_mm, date_yyyy, date_yyyymm, date_mmstr)
      CSV.generate(col_sep: "|", encoding: 'windows-1252', row_sep: "\r\n") do |csv|
        obj_conta_agrupado.each.with_index(1) do |(k, v), index|
          print_data(csv, k, v, index, dolar)
        end
      end
    end

    def group_data obj_contabilidad, date_dd_mm_yyyy, date_mm, date_yyyy, date_yyyymm, date_mmstr
      obj_contabilidad.group_by do |l|
        account, account_type = cuenta_contable(l)
        centro_costo, glosa, cod_tdc, cod_aux, ser_doc, nro_doc, doc_employee = get_data(l, date_yyyymm)
        {
          mm: date_mmstr.capitalize,
          year: date_yyyy,
          month: date_mm,
          date: date_dd_mm_yyyy,
          cod_asiento: l.cuenta_custom_attrs["Número de asiento"].to_s,
          asiento: l.cuenta_custom_attrs['Tipo de asiento'],
          centro_costo: centro_costo,
          cod_tdc: cod_tdc,
          cod_aux: get_cod_aux(l, cod_aux),
          cod_aux_2: doc_employee,
          ser_doc: ser_doc,
          nro_doc: nro_doc,
          cuenta_contable: account || l.cuenta_contable,
          tip_cuenta: account_type,
          glosa: glosa,
          deber_o_haber: l.deber_o_haber,
          cod_detalle: l.cuenta_custom_attrs["TPODLLE"],
        }
      end
    end

    def cuenta_contable(l)
      plan_contable = "#{l.centro_costo}-#{l.job_custom_attrs["Moneda de pago"]}"
      tipo_moneda = l.job_custom_attrs["Moneda de pago"] == "D" ? "E" : "N"
      return [l.cuenta_custom_attrs[plan_contable], tipo_moneda] unless l.cuenta_custom_attrs["AFP"].to_s.casecmp('si').zero?
      [search_account(l), tipo_moneda]
    end

    def cod_auxiliar l, date_yyyymm
      ["00", l.employee_custom_attrs["CODAUX"], "PLLA", "0000#{date_yyyymm}"] if l.cuenta_custom_attrs["CODAUX"].to_s.casecmp('si').zero?
    end

    def get_data l, date_yyyymm
      cod_tdc, cod_aux, ser_doc, nro_doc = cod_auxiliar(l, date_yyyymm)
      case l.cuenta_custom_attrs&.dig("Agrupador")
      when 'CENCO'
        [search_cenco(l), l.glosa, nil, nil, nil, nil, nil]
      when 'TOTAL'
        [nil, l.glosa, nil, nil, nil, nil, nil]
      when 'DNI'
        [search_cenco(l), l.glosa, cod_tdc, cod_aux, ser_doc, nro_doc, l.numero_documento.to_s]
      when 'AFP'
        [nil, l.afp, cod_tdc, cod_aux, ser_doc, nro_doc, nil]
      end
    end

    def print_data csv, k, v, index, dolar
      csv << [
        k[:year],
        "0401",
        k[:cod_asiento],
        k[:month],
        k[:date],
        "#{k[:asiento]} #{k[:mm]} #{k[:year]}",
        nil,
        "D",
        index.to_s.rjust(4, '0'),
        index.to_s.rjust(4, '0'),
        k[:cod_tdc],
        k[:cuenta_contable],
        k[:centro_costo],
        k[:cod_aux],
        k[:ser_doc],
        k[:nro_doc],
        k[:date],
        k[:date],
        k[:date],
        k[:cod_aux_2],
        k[:glosa],
        nil,
        k[:deber_o_haber] == "D" ? "D" : "H",
        k[:cod_detalle],
        k[:tip_cuenta],
        "V",
        dolar,
        format("%#.2f", v.sum(&:monto).to_f.round(2)),
        format("%#.2f", (v.sum(&:monto).to_f.round(2) / dolar)),
        nil,
        index.to_s.rjust(4, '0'),
        nil,
      ]
    end

    def descartar_cuentas(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_INFORMATIVOS.include?(l.nombre_cuenta)
      end
    end

    def get_cod_aux l, cod_aux
      cod_aux if l.cuenta_custom_attrs["CODAUX"].to_s.casecmp('si').zero?
    end

end

# EXAMPLE 36
#andesexpresssac.rb


# frozen_string_literal: true

# Archivo de Centralizacion Personalizada cliente Andes Express Perú
class Exportador::Contabilidad::Peru::Personalizadas::Andesexpresssac < Exportador::Contabilidad::Peru::CentralizacionContable
  def initialize
    super()
    @extension = 'xlsx'
  end

  HEADER = [
    'MES',
    'T',
    'VOUCHER',
    'FECHA',
    'Cuenta ',
    'DESCRIPCION',
    'DEBE',
    'HABER',
    'MONEDA',
    'TC',
    'DOC',
    'NUMERO DOC',
    'FECHA D',
    'FECHA V',
    'CODIGO RUC',
    'CC',
    'Glosa',
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    grouped = obj_contabilidad.group_by{|obj| obj.cuenta_custom_attrs['Tipo de asiento'] || "Otros"}
    grouped.map do |k, v|
      libro = excel_data(empresa, variable, v)
      ["file_#{k}", Exportador::Contabilidad::AccountingFile.new(contents: libro, name_formatter: -> (name) { "#{name}-#{k}" })]
    end.to_h
  end

  def excel_data(empresa, variable, obj_contabilidad)
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    Exportador::BaseXlsx.crear_encabezado(sheet, HEADER, 0)
    month = I18n.l(variable.end_date, format: '%m')
    end_date = I18n.l(variable.end_date, format: '%d/%m/%Y')
    month_year = I18n.l(variable.end_date, format: '%m%Y')
    month_word_year = I18n.l(variable.end_date, format: '%B %Y').upcase
    tipo_cambio = empresa.custom_attrs['TC']

    grouper = obj_contabilidad.group_by do |l|
      {
        account: search_account(l),
        deber_o_haber: l.deber_o_haber,
        cencos: search_cenco(l),
        descripcion: search_glosa_afp(l).to_s,
        codigo_ruc: search_ruc(l),
        fechad: fechad(l, month_word_year),
      }
    end

    data = grouper.lazy.map do |k, v|
      [
        month,
        '07',
        '2',
        end_date,
        k[:account],
        k[:descripcion],
        k[:deber_o_haber] == 'D' ? v.sum(&:monto) : 0,
        k[:deber_o_haber] == 'C' ? v.sum(&:monto) : 0,
        "S",
        tipo_cambio,
        '00',
        month_year,
        end_date,
        end_date,
        k[:codigo_ruc],
        k[:cencos],
        k[:fechad],
      ]
    end
    Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 1
    Exportador::BaseXlsx.autofit sheet, [HEADER]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  private

    def fechad l, end_date
      "#{l.cuenta_custom_attrs["Tipo de asiento"]} #{end_date}"
    end
end

# EXAMPLE 37
#pullman_hotel.rb


# Clase para generar contabilidad personalizada de PullmanHotel
class Exportador::Contabilidad::Peru::Personalizadas::PullmanHotel < Exportador::Contabilidad
  def initialize
    super()
    @extension = 'xlsx'
  end
  def create_lineas_liquidacion(liquidacions, **args)
    ::Contabilidad::Peru::LineasLiquidacionesService.new(liquidacions, **args)
  end
  TITULO1 = [
    'fec_movimi',
    'mes_movimi',
    'cdo_fuente',
    'cdo_cuenta',
    'cdo_auxil1',
    'cdo_auxil2',
    'cdo_auxil3',
    'cdo_refere',
    'tip_docume',
    'num_docume',
    'monto_debe',
    'monto_habe',
    'dolar_debe',
    'dolar_habe',
    'des_movimi',
    'nom_girado',
    'cdo_usuari',
    'fec_vencim',
    'tip_docref',
    'num_docref',
    'med_pago',
    'cdo_auxil4',
    'cdo_entren',
    'tip_cambio',
    'gto_deduci',
    'cdo_moneda',
    'cdo_bieser',
  ].freeze
  TITULO2 = ['Tipo Cuenta', 'Concepto', 'Descripcion Concepto', 'Numero Cuenta', 'Importe Cuenta'].freeze
  PROVISION = ['Planilla de Provisión de CTS', 'Provisión de Gratificación', 'Provision Vacaciones', 'Finiquito'].freeze
  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    sheet2 = Exportador::BaseXlsx.crear_hoja book, "AsientoContableCalculo"
    sheet3 = Exportador::BaseXlsx.crear_hoja book, "provision_cts"
    sheet4 = Exportador::BaseXlsx.crear_hoja book, "provision_vacaciones"
    sheet5 = Exportador::BaseXlsx.crear_hoja book, "provision_gratificacion"
    sheet6 = Exportador::BaseXlsx.crear_hoja book, "finiquitos"
    suma_deberes = obj_contabilidad.select(&:deber?).reject{|l| PROVISION.include?(l.cuenta_custom_attrs&.dig("Nombre de la cuenta"))}.sum(&:monto)&.to_i
    suma_haberes = obj_contabilidad.reject{|l| l.deber_o_haber == 'D' || PROVISION.include?(l.cuenta_custom_attrs&.dig("Nombre de la cuenta"))}.sum(&:monto)&.to_i
    array_data = []
    fecha = variable.end_date.strftime('%d/%m/%Y')
    mes = variable.end_date.strftime('%m')
    Exportador::BaseXlsx.escribir_celdas sheet, [TITULO1], offset: 0
    Exportador::BaseXlsx.escribir_celdas sheet2, [TITULO2], offset: 0
    Exportador::BaseXlsx.escribir_celdas sheet3, [TITULO1], offset: 0
    Exportador::BaseXlsx.escribir_celdas sheet4, [TITULO1], offset: 0
    Exportador::BaseXlsx.escribir_celdas sheet5, [TITULO1], offset: 0
    Exportador::BaseXlsx.escribir_celdas sheet6, [TITULO1], offset: 0
    agrupado = ["CENCOS", "CONCEPTO"].freeze
    #hoja 1
    complemento = complemento_fun(obj_contabilidad, agrupado)

    #hoja 2
    group = group_fun(obj_contabilidad, agrupado)

    #hoja 3 provision_cts
    group_prov_cts = provision_cts(obj_contabilidad).sort_by{|o| [o.deber_o_haber]}.group_by do |o|
      conjunto(o)
    end
    #hoja 4 provision_vacaciones
    group_prov_vac = provision_v(obj_contabilidad).sort_by{|o| [o.deber_o_haber]}.group_by do |o|
      conjunto(o)
    end
    #hoja 5 provision_gratificacion
    group_prov_grat = provision_g(obj_contabilidad).sort_by{|o| [o.deber_o_haber]}.group_by do |o|
      conjunto(o)
    end
    #hoja 6 finiquitos
    group_finiquitos = finiquitos(obj_contabilidad).sort_by{|o| [o.deber_o_haber]}.group_by do |o|
      conjunto(o)
    end
    excel_data_detalles = print_detalle(complemento, fecha, mes)
    excel_data_agrupados = print_agrupados(group, fecha, mes)
    excel_data_prov_cts = print_agrupados(group_prov_cts, fecha, mes)
    excel_data_prov_vac = print_agrupados(group_prov_vac, fecha, mes)
    excel_data_prov_grat = print_agrupados(group_prov_grat, fecha, mes)
    excel_data_finiquito = print_agrupados(group_finiquitos, fecha, mes)
    total_deber = obj_contabilidad.select{|l| l.deber_o_haber == 'D'}.reject{|l| PROVISION.include?(l.cuenta_custom_attrs&.dig("Nombre de la cuenta"))}.group_by do |o|
      conjunto_asiento(o)
    end
    total_haber = obj_contabilidad.reject{|l| l.deber_o_haber == 'D' || PROVISION.include?(l.cuenta_custom_attrs&.dig("Nombre de la cuenta"))}.group_by do |o|
      conjunto_asiento(o)
    end

    total_deber.map do |k, v|
      array_data << array_data_haber_deber(k, v)
    end
    array_data << [nil, nil, nil, "TOTAL DEBE :", suma_deberes.to_i, nil, nil, nil]

    total_haber.map do |k, v|
      array_data << array_data_haber_deber(k, v)
    end
    array_data << [nil, nil, nil, "TOTAL HABER :", suma_haberes.to_i, nil, nil, nil]

    excel_data  = excel_data_detalles + excel_data_agrupados

    Exportador::BaseXlsx.escribir_celdas sheet, excel_data, offset: 1, number_format: '#,##0'
    Exportador::BaseXlsx.escribir_celdas sheet2, array_data, offset: 1, number_format: '#,##0'
    Exportador::BaseXlsx.escribir_celdas sheet3, excel_data_prov_cts, offset: 1, number_format: '#,##0'
    Exportador::BaseXlsx.escribir_celdas sheet4, excel_data_prov_vac, offset: 1, number_format: '#,##0'
    Exportador::BaseXlsx.escribir_celdas sheet5, excel_data_prov_grat, offset: 1, number_format: '#,##0'
    Exportador::BaseXlsx.escribir_celdas sheet6, excel_data_finiquito, offset: 1, number_format: '#,##0'
    Exportador::BaseXlsx.autofit sheet, [TITULO1]
    Exportador::BaseXlsx.autofit sheet2, [TITULO2]
    Exportador::BaseXlsx.autofit sheet3, [TITULO1]
    Exportador::BaseXlsx.autofit sheet4, [TITULO1]
    Exportador::BaseXlsx.autofit sheet5, [TITULO1]
    Exportador::BaseXlsx.autofit sheet6, [TITULO1]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end
  private
    def search_concepto object
      return object.glosa if object.cuenta_custom_attrs&.dig("Agrupador")&.upcase == "CONCEPTO"
      object.cuenta_custom_attrs&.dig("Nombre cuenta Contable")
    end
    def search_cenco object
      object.centro_costo if object.cuenta_custom_attrs&.dig("Agrupador")&.upcase == "CENCOS" || object.deber?
    end
    def search_aux object
      centro_costo = search_cenco(object).to_s[1..8]
      if object.centro_costo.present? && object.deber?
        "E#{centro_costo}"
      end
    end
    def array_data_haber_deber(k, v)
      [
        k[:deber_o_haber] == 'C' ? "HABER" : "DEBER",
        k[:concepto],
        k[:glosa],
        k[:cuenta_contable],
        v.sum(&:monto),
      ]
    end
    def conjunto(o)
      {
        cuenta_contable: o.cuenta_contable,
        concepto: o.item_code,
        aux: o.deber? ? I18n.transliterate(search_aux(o)).presence : nil,
        centro_costo: o.deber? ? I18n.transliterate(search_cenco(o)).presence : nil,
        deber_o_haber: o.deber_o_haber,
        glosa: I18n.transliterate(o.cuenta_custom_attrs&.dig("Nombre de la cuenta")).presence || o.glosa,
      }
    end

    def conjunto_asiento(o)
      {
        cuenta_contable: o.cuenta_contable,
        concepto: I18n.transliterate(o.cuenta_custom_attrs&.dig("Concepto")),
        deber_o_haber: o.deber_o_haber,
        glosa: o.glosa,
      }
    end

    def print_detalle complemento, fecha, mes
      complemento.map do |l|
        [
          fecha,
          mes,
          "C",
          l.cuenta_contable,
          search_aux(l),
          search_cenco(l),
          nil,
          nil,
          nil,
          nil,
          l.deber.presence || 0,
          l.haber.presence || 0,
          "0.00",
          "0.00",
          l.cuenta_custom_attrs&.dig("Nombre de la cuenta"),
          nil,
          "ADM",
          nil,
          nil,
          nil,
          nil,
          nil,
          nil,
          "0.00",
          nil,
          nil,
          nil,
        ]
      end
    end
    def print_agrupados group, fecha, mes
      group.map do |k, v|
        [
          fecha,
          mes,
          "C",
          k[:cuenta_contable],
          k[:aux],
          k[:centro_costo],
          nil,
          nil,
          nil,
          nil,
          k[:deber_o_haber] == "D" ? v.sum(&:monto) : 0,
          k[:deber_o_haber] == "C" ? v.sum(&:monto) : 0,
          "0.00",
          "0.00",
          k[:glosa],
          nil,
          "ADM",
          nil,
          nil,
          nil,
          nil,
          nil,
          nil,
          "0.00",
          nil,
          nil,
          nil,
        ]
      end
    end

    def provision_cts obj
      obj.select{|o| o.cuenta_custom_attrs&.dig("Nombre de la cuenta") == 'Planilla de Provisión de CTS'}
    end
    def provision_g obj
      obj.select{|o| o.cuenta_custom_attrs&.dig("Nombre de la cuenta") == 'Provisión de Gratificación'}
    end
    def provision_v obj
      obj.select{|o| o.cuenta_custom_attrs&.dig("Nombre de la cuenta") == 'Provision Vacaciones'}
    end
    def finiquitos obj
      obj.select{|o| o.cuenta_custom_attrs&.dig("Nombre de la cuenta") == 'Finiquito'}
    end

    def complemento_fun obj_contabilidad, agrupado
      obj_contabilidad.select{|o| o.formato == 'detalle'}.reject{|o| agrupado.include?(o.cuenta_custom_attrs&.dig("Agrupador")) || PROVISION.include?(o.cuenta_custom_attrs&.dig("Nombre de la cuenta"))}.sort_by{|o| [o.deber_o_haber]}
    end

    def group_fun obj_contabilidad, agrupado
      obj_contabilidad.select{|o| agrupado.include?(o.cuenta_custom_attrs&.dig("Agrupador")) || o.formato == 'resumen'}.reject{|o| PROVISION.include?(o.cuenta_custom_attrs&.dig("Nombre de la cuenta"))}.group_by do |o|
        conjunto(o)
      end
    end
end

# EXAMPLE 38
#corporacion_enerjet.rb


# frozen_string_literal: true

#Centralización personalizada para empresa Corporación Enerjet Perú
class Exportador::Contabilidad::Peru::Personalizadas::CorporacionEnerjet < Exportador::Contabilidad
  include ContabilidadPeruHelper
  def initialize
    super()
    @extension = 'xls'
  end

  HEADERS_1 = [
    'AccountCode',
    '',
    'Debit',
    'Credit',
    'Name',
    '',
    '',
    'Short Name',
    '',
    'CECO3',
    'CECO 2',
  ].freeze

  HEADERS_2 = [
    'AccountCode',
    '',
    '',
    'CECO3',
    'Debit',
    'Credit',
    'Name',
    'Tipo de asiento',
  ].freeze

  def generate_doc(empresa, _variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    obj_obreros = obj_contabilidad.reject{|l| l.employee_custom_attrs['Plan Contable'] == 'Empleados'}
    obj_empleados = obj_contabilidad.select{|l| l.employee_custom_attrs['Plan Contable'] == 'Empleados'}

    obj_obrero_agrupado = obj_obreros.group_by{|l| l.cuenta_custom_attrs["Tipo de asiento"].presence || "Sin_Asiento"}
    obj_empleados_agrupado = obj_empleados.group_by{|l| l.cuenta_custom_attrs["Tipo de asiento"].presence || "Sin_Asiento"}
    centralizacion_a_generar = empresa.custom_attrs["Formato"].to_s == "EGA"

    libros = {}

    obj_obrero_agrupado.each do |k, v|
      libro = centralizacion_a_generar ? generate_centralizacion_ega(empresa, v) : generate_centralizacion(empresa, v, k)
      libros["Libro_Obreros_#{k}".to_sym] = Exportador::Contabilidad::AccountingFile.new(contents: libro, name_formatter: -> (name) {"#{k} Obreros - #{name}"})
    end

    obj_empleados_agrupado.each do |k, v|
      libro = centralizacion_a_generar ? generate_centralizacion_ega(empresa, v) : generate_centralizacion(empresa, v, k)
      libros["Libro_Empleados_#{k}".to_sym] = Exportador::Contabilidad::AccountingFile.new(contents: libro, name_formatter: -> (name) {"#{k} Empleados - #{name}"})
    end

    libros
  end

  def generate_centralizacion_ega(empresa, obj)
    book = Exportador::Base.crear_libro
    sheet = book.create_worksheet name: empresa.nombre

    sheet.row(0).concat HEADERS_1

    obj.sort_by(&:deber_o_haber).reverse.each_with_index do |l, index|
      sheet.row(index + 1).push(
        cuenta_por_plan_y_afp(l),
        nil,
        l.deber.presence || 0,
        l.haber.presence || 0,
        l.employee.apellidos_nombre,
        nil,
        nil,
        l.numero_documento.to_s,
        "1",
        l.centro_costo,
        l.employee_custom_attrs["Sede"].to_s[0..2],
      )
    end
    Exportador::Base.autofit sheet
    Exportador::Base.cerrar_libro(book).contenido
  end

  def generate_centralizacion(empresa, obj, tipo_asiento)
    book = Exportador::Base.crear_libro
    sheet = book.create_worksheet name: empresa.nombre

    sheet.row(0).concat HEADERS_2

    obj.sort_by(&:deber_o_haber).reverse.each_with_index do |l, index|
      sheet.row(index + 1).push(
        cuenta_por_plan_y_afp(l),
        nil,
        "1",
        l.centro_costo,
        l.deber.presence || 0,
        l.haber.presence || 0,
        l.employee.apellidos_nombre,
        tipo_asiento,
      )
    end
    Exportador::Base.autofit sheet
    Exportador::Base.cerrar_libro(book).contenido
  end

  private

    def cuenta_por_plan_y_afp(l)
      plan_contable = l.employee_custom_attrs&.dig("Plan Contable").to_s

      if l.cuenta_custom_attrs["AFP"].to_s.casecmp('si').zero?
        cuenta_afp = afp_method(l)
        cuenta_afp.custom_attrs&.dig(plan_contable).presence || cuenta_afp.numero
      else
        l.cuenta_custom_attrs&.dig(plan_contable)
      end.presence || l.cuenta_contable
    end
end

# EXAMPLE 39
#eglo.rb


# frozen_string_literal: true

#
#Clase para la centralizacion personalizada cliente Eglo
class Exportador::Contabilidad::Peru::Personalizadas::Eglo < Exportador::Contabilidad::Peru::CentralizacionContable
  def initialize
    super()
    @extension = 'xlsx'
  end

  CABECERA = [
    'Item',
    'Cuenta',
    'Descripción',
    'M',
    'Debe',
    'Haber',
    'T.Cambio',
    'Documento',
    'Deudor/Acreedor',
    'Fecha documento',
    'C.Costo',
  ].freeze

  NO_CONTABILIZAR_INFORMATIVOS = [
    'provision_bonificacion_extraordinaria_gratificacion_deber',
    'provision_bonificacion_extraordinaria_gratificacion_haber',
    'provision_gratificacion_deber',
    'provision_gratificacion_haber',
    'provision_bonificacion_extraordinaria_mensual_contabilizar_haber',
    'provision_bonificacion_extraordinaria_mensual_contabilizar_deber',
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    grouped = obj_contabilidad.group_by{|obj| obj.cuenta_custom_attrs['Tipo de asiento'] || "Otros"}
    grouped.map do |k, v|
      libro = excel_data(empresa, variable, v)
      ["file_#{k}", Exportador::Contabilidad::AccountingFile.new(contents: libro, name_formatter: -> (name) { "#{name}-#{k}" })]
    end.to_h
  end

  def excel_data(empresa, variable, obj_contabilidad)
    tipo_cambio = kpi_dolar(variable.id, empresa.id)

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)

    full_date = I18n.l(date, format: "%d-%-m-%y")
    date_mmyyyy = I18n.l(date, format: "%m%Y")

    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, "ASIENTOS"
    Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA, 0)

    obj_contabilidad = descartar_informativos(obj_contabilidad)

    agrupado = obj_contabilidad.group_by do |obj|
      {
        glosa: search_glosa_afp(obj),
        deber_haber: obj.deber_o_haber,
        deudor_acreedor: get_deudor_acreedor(obj),
        cenco: get_cenco(obj),
        cuenta: get_cuenta_by_plan_contable_dinamico(obj, 'job'),
      }
    end

    data = agrupado.map.with_index do |(k, v), index|
      item_number = index + 1
      [
        item_number.to_s.rjust(4, "0"),
        k[:cuenta],
        k[:glosa],
        "S/",
        k[:deber_haber] == "D" ? v.sum(&:monto) : nil,
        k[:deber_haber] == "C" ? v.sum(&:monto) : nil,
        tipo_cambio,
        "00-#{date_mmyyyy}",
        k[:deudor_acreedor],
        full_date,
        k[:cenco],
      ]
    end

    Exportador::BaseXlsx.autofit sheet, [CABECERA]
    Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 1, number_format: "###,###,##0.00"
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  private

    def get_cenco obj
      obj.centro_costo if (obj.cuenta_custom_attrs&.dig("Agrupador") == "DNI" || obj.cuenta_custom_attrs&.dig("Agrupador") == "Cenco") && obj.cuenta_custom_attrs&.dig("Centro Costos")
    end
    def descartar_informativos(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_INFORMATIVOS.include?(l.nombre_cuenta)
      end
    end
    def get_deudor_acreedor obj
      obj.numero_documento if obj.cuenta_custom_attrs&.dig("Agrupador") == 'DNI'
    end
end

# EXAMPLE 40
#petromont.rb


#frozen_string_literal: true

#Centralizacion personalizada Petromont PE, formato xls
class Exportador::Contabilidad::Peru::Personalizadas::Petromont < Exportador::Contabilidad
  def initialize
    super
    @extension = "xls"
  end

  HEADERS = ['AREA',
             'LOCAL',
             'SUB.DIARIO',
             'FCH.DOC',
             'CUENTA',
             'CCOSTO',
             'UNIDAD_COSTO',
             'COD.AUXILIAR',
             'MONEDA',
             'TCAMBIO',
             'DEBE ',
             'HABER',
             'DEBE',
             'HABER',
             'DEBE',
             'HABER',
             'TIP.DOC',
             'SERIE',
             'NUMERO',
             'GLOSA',].freeze
  CABECERA_3 = ["TOTAL DEL DOCUMENTO",
                nil,
                nil,
                nil,
                nil,
                nil,
                nil,
                nil,
                nil,
                nil,
                "MON. NACIONAL",
                nil,
                "MON. CONVERSION",
                nil,
                "MON. EXTRANJERA",].freeze
  CABECERA_4 = [nil,
                nil,
                nil,
                nil,
                nil,
                nil,
                nil,
                nil,
                nil,
                nil,
                "DEBE",
                "HABER",
                "DEBE",
                "HABER",
                "DEBE",
                "HABER",].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?
    book = Exportador::Base.crear_libro
    fecha = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    obj_obrero = obj_contabilidad.select{|o| o.employee_custom_attrs&.dig("Tipo de Trabajador") == "Obrero"}
    obj_empleado = obj_contabilidad.reject{|o| o.employee_custom_attrs&.dig("Tipo de Trabajador") == "Obrero"}
    generate_document(empresa, variable, obj_obrero, book, "Obreros", fecha)
    generate_document(empresa, variable, obj_empleado, book, "Empleados", fecha)
    Exportador::Base.cerrar_libro(book).contenido
  end
  def generate_document(empresa, variable, obj_contabilidad, book, name, fecha)
    return unless obj_contabilidad.present?
    sheet = book.create_worksheet name: name
    tipo_cambio = kpi_cambio(variable.id, empresa.id) || 1
    cabecera_1 = ["ASIENTO:", empresa.nombre.capitalize]
    cabecera_2 = ["EMPRESA:", empresa.custom_attrs["Codigo"]]
    agrupador = obj_contabilidad.group_by do |obj|
      {
        unidad_negocio: get_unidad_negocio(variable, obj),
        tipo_trabajador: get_tipo_trabajador(obj),
        cuenta_contable: get_cuenta_contable(obj),
        unidad_costo: get_unidad_costo(variable, obj),
        documento_empleado: get_doc_empleado(obj),
        descripcion: get_descripcion_prestamo(obj, fecha),
        glosa: "#{obj.tipo_doc} #{I18n.l(fecha, format: "%B %Y").capitalize}",
        cenco: search_cenco(obj),
        deber_haber: obj.deber_o_haber,
      }
    end
    sheet.row(0).concat(cabecera_1)
    sheet.row(1).concat(cabecera_2)
    sheet.row(2).concat(CABECERA_3)
    sheet.row(3).concat(CABECERA_4)
    sheet.row(7).concat(HEADERS)
    agrupador.each.with_index(8) do |(k, v), index|
      sheet.row(index).push(
        k[:unidad_negocio],
        "0",
        k[:tipo_trabajador],
        "0",
        k[:cuenta_contable],
        k[:cenco],
        k[:unidad_costo],
        k[:documento_empleado],
        "01",
        tipo_cambio,
        k[:deber_haber] == "D" ? v.sum(&:monto) : 0,
        k[:deber_haber] == "C" ? v.sum(&:monto) : 0,
        k[:deber_haber] == "D" ? (v.sum(&:monto).to_f / tipo_cambio).round(2) : 0,
        k[:deber_haber] == "C" ? (v.sum(&:monto).to_f / tipo_cambio).round(2) : 0,
        k[:deber_haber] == "D" ? (v.sum(&:monto).to_f / tipo_cambio).round(2) : 0,
        k[:deber_haber] == "C" ? (v.sum(&:monto).to_f / tipo_cambio).round(2) : 0,
        "PL",
        "0000",
        k[:descripcion],
        k[:glosa],
      )
    end
  end
  private
    def kpi_cambio variable_id, empresa_id
      @kpi_dolar ||= Hash.new do |h, empresa_id_arg|
        conditions = {
          variable_id: variable_id,
          empresa_id: empresa_id_arg,
          kpis: { code: "tipo_cambio"},
        }
        h[empresa_id_arg] = KPIDatum.joins(:kpi).where(conditions).single_or_nil!&.decimal_value
      end
      @kpi_dolar[empresa_id]
    end

    def get_unidad_negocio(variable, obj)
      parameter = obj.employee_custom_attrs&.dig("Unidad de Negocio")
      return unless parameter.present?
      tabla(variable).lookup_column("unidades_negocios", "Descripcion", parameter, "Codigo")
    end

    def get_tipo_trabajador(obj)
      tipo_trabajador = obj.employee_custom_attrs&.dig("Tipo de Trabajador")
      return unless tipo_trabajador.present?
      tipo_trabajador == "Empleado" ? "112" : "012"
    end

    def get_unidad_costo(variable, obj)
      return unless get_cuenta_contable(obj).to_s&.start_with?("6")
      parameter = obj.employee_custom_attrs&.dig("Unidad de Costo")
      return unless parameter.present?
      tabla(variable).lookup_column("unidad_costo", "Descripcion unidad costo", parameter, "Unidad costo")
    end

    def get_descripcion_prestamo(obj, fecha)
      case obj.nombre_cuenta
      when "prestamo personal"
        obj.description&.tr("()", "")
      when "subsidios", "descuento_cooperativa"
        fecha.strftime("%Y%m")
      end
    end

    def get_cuenta_contable(obj)
      tipo_trabajador = obj.employee_custom_attrs&.dig("Tipo de Trabajador")
      return unless tipo_trabajador.present?
      obj.cuenta_custom_attrs&.dig(tipo_trabajador) || obj.cuenta_contable
    end

    def tabla variable
      @tabla ||= Hash.new do |h, key|
        h[key] = CalculosBono::ParameterTableLookup.new(key)
      end
      @tabla[variable]
    end
    def search_cenco(obj)
      obj.centro_costo_custom_attrs&.dig("Descripcion") if get_cuenta_contable(obj)&.start_with?("6")
    end
    def get_doc_empleado(obj)
      obj.numero_documento&.humanize if obj.cuenta_custom_attrs&.dig("Agrupador") == "COD AUXILIAR"
    end
end

# EXAMPLE 41
#transportes_montano_eirl.rb


# frozen_string_literal: true

#Clase para la centralizacion personaliza cliente Transportes Montano EIRL
class Exportador::Contabilidad::Peru::Personalizadas::TransportesMontanoEirl < Exportador::Contabilidad
  include ContabilidadPeruHelper
  def initialize
    super
    @extension = "xlsx"
  end

  HEADERS_1 = [
    'Campo',
    'Sub Diario',
    'Número de Comprobante',
    'Fecha de Comprobante',
    'Código de Moneda',
    'Glosa Principal',
    'Tipo de Cambio',
    'Tipo de Conversión',
    'Flag de Conversión de Moneda',
    'Fecha Tipo de Cambio',
    'Cuenta Contable',
    'Código de Anexo',
    'Código de Centro de Costo',
    'Debe / Haber',
    'Importe Original',
    'Importe en Dólares',
    'Importe en Soles',
    'Tipo de Documento',
    'Número de Documento',
    'Fecha de Documento',
    'Fecha de Vencimiento',
    'Código de Area',
    'Glosa Detalle',
    'Código de Anexo Auxiliar',
    'Medio de Pago',
    'Tipo de Documento de Referencia',
    'Número de Documento Referencia',
    'Fecha Documento Referencia',
    'Nro Máq. Registradora Tipo Doc. Ref.',
    'Base Imponible Documento Referencia',
    'IGV Documento Provisión',
    'Tipo Referencia en estado MQ',
    'Número Serie Caja Registradora',
    'Fecha de Operación',
    'Tipo de Tasa',
    'Tasa Detracción/Percepción',
    'Importe Base Detracción/Percepción Dólares',
    'Importe Base Detracción/Percepción Soles',
    'Tipo Cambio para F',
    'Importe de IGV sin derecho crédito fiscal',
  ].freeze

  HEADERS_2 = [
    'Restricciones',
    'Ver T.G. 02',
    'Los dos primeros dígitos son el mes y los otros 4 siguientes un correlativo',
    nil,
    'Ver T.G. 03',
    nil,
    "Llenar solo si Tipo de Conversión es 'C'. Debe estar entre >=0 y <=9999.999999",
    "Solo: 'C'= Especial, 'M'=Compra, 'V'=Venta , 'F' De acuerdo a fecha",
    "Solo: 'S' = Si se convierte, 'N'= No se convierte",
    "Si  Tipo de Conversión 'F'",
    "Debe existir en el Plan de Cuentas",
    "Si Cuenta Contable tiene seleccionado Tipo de Anexo, debe existir en la tabla de Anexos",
    "Si Cuenta Contable tiene habilitado C. Costo, Ver T.G. 05",
    "'D' ó 'H'",
    "Importe original de la cuenta contable. Obligatorio, debe estar entre >=0 y <=99999999999.99",
    "Importe de la Cuenta Contable en Dólares. Obligatorio si Flag de Conversión de Moneda esta en 'N', debe estar entre >=0 y <=99999999999.99",
    "Importe de la Cuenta Contable en Soles. Obligatorio si Flag de Conversión de Moneda esta en 'N', debe estra entre >=0 y <=99999999999.99",
    "Si Cuenta Contable tiene habilitado el Documento Referencia Ver T.G. 06",
    "Si Cuenta Contable tiene habilitado el Documento Referencia Incluye Serie y Número",
    "Si Cuenta Contable tiene habilitado el Documento Referencia",
    "Si Cuenta Contable tiene habilitada la Fecha de Vencimiento",
    "Si Cuenta Contable tiene habilitada el Area. Ver T.G. 26",
    nil,
    "Si Cuenta Contable tiene seleccionado Tipo de Anexo Referencia",
    "Si Cuenta Contable tiene habilitado Tipo Medio Pago. Ver T.G. 'S1'",
    "Si Tipo de Documento es 'NA' ó 'ND' Ver T.G. 06",
    "Si Tipo de Documento es 'NC', 'NA' ó 'ND', incluye Serie y Número",
    "Si Tipo de Documento es 'NC', 'NA' ó 'ND'",
    "Si Tipo de Documento es 'NC', 'NA' ó 'ND'. Solo cuando el Tipo Documento de Referencia 'TK'",
    "Si Tipo de Documento es 'NC', 'NA' ó 'ND'",
    "Si Tipo de Documento es 'NC', 'NA' ó 'ND'",
    "Si la Cuenta Contable tiene Habilitado Documento Referencia 2 y  Tipo de Documento es 'TK'",
    "Si la Cuenta Contable teien Habilitado Documento Referencia 2 y  Tipo de Documento es 'TK'",
    "Si la Cuenta Contable tiene Habilitado Documento Referencia 2. Cuando Tipo de Documento es 'TK', consignar la fecha de emision del ticket",
    "Si la Cuenta Contable tiene configurada la Tasa:  Si es '1' ver T.G. 28 y '2' ver T.G. 29",
    "Si la Cuenta Contable tiene conf. en Tasa:  Si es '1' ver T.G. 28 y '2' ver T.G. 29. Debe estar entre >=0 y <=999.99",
    "Si la Cuenta Contable tiene configurada la Tasa. Debe ser el importe total del documento y estar entre >=0 y <=99999999999.99",
    "Si la Cuenta Contable tiene configurada la Tasa. Debe ser el importe total del documento y estar entre >=0 y <=99999999999.99",
    "Especificar solo si Tipo Conversión es 'F'. Se permite 'M' Compra y 'V' Venta.",
    "Especificar solo para comprobantes de compras con IGV sin derecho de crédito Fiscal. Se detalle solo en la cuenta 42xxxx",
  ].freeze

  HEADERS_3 = [
    "Tamaño/Formato",
    "4 Caracteres",
    "6 Caracteres",
    "dd/mm/aaaa",
    "2 Caracteres",
    "40 Caracteres",
    "Numérico 11, 6",
    "1 Caracteres",
    "1 Caracteres",
    "dd/mm/aaaa",
    "12 Caracteres",
    "18 Caracteres",
    "6 Caracteres",
    "1 Carácter",
    "Numérico 14,2",
    "Numérico 14,2",
    "Numérico 14,2",
    "2 Caracteres",
    "20 Caracteres",
    "dd/mm/aaaa",
    "dd/mm/aaaa",
    "3 Caracteres",
    "30 Caracteres",
    "18 Caracteres",
    "8 Caracteres",
    "2 Caracteres",
    "20 Caracteres",
    "dd/mm/aaaa",
    "20 Caracteres",
    "Numérico 14,2 ",
    "Numérico 14,2",
    "'MQ'",
    "15 caracteres",
    "dd/mm/aaaa",
    "5 Caracteres",
    "Numérico 14,2",
    "Numérico 14,2",
    "Numérico 14,2",
    "1 Caracter",
    "Numérico 14,2",
  ].freeze


  TIPO_ASIENTO = {
    "NOMINA" => ["0001", "PLANILLA"],
    "CTS" => ["0001", "CTS"],
    "LIQUIDACION" => ["0002", "LIQUIDACIONES"],
    "PROV GRAT" => ["0003", "PROVISION GRATIFICACION"],
    "PROV CTS" => ["0004", "PROVISION CTS"],
    "PROV VAC" => ["0005", "PROVISION VACACIONES"],
    "SIN_TIPO_ASIENTO" => ["0000", "Sin asiento"],
  }.freeze

  NO_CONTABILIZAR_INFORMATIVOS = [
    "buk_provision_vacaciones",
    "buk_provision_gratificacion",
    "buk_provision_cts",
    "buk_provision_bonificacion_gratificacion",
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    libros = {}
    obj_contabilidad = descartar_informativos(obj_contabilidad)

    obj_contabilidad_agrupado = obj_contabilidad.group_by{|l| l.cuenta_custom_attrs["Tipo de Asiento"].presence || "SIN_TIPO_ASIENTO"}

    obj_contabilidad_agrupado.each do |k, obj|
      libro = generate_doc_por_tipo_asiento(empresa, variable, obj, k)
      libros["Libro_#{k}".to_sym] = Exportador::Contabilidad::AccountingFile.new(contents: libro, name_formatter: -> (name) {"#{k} #{name}"})
    end
    libros
  end

  def generate_doc_por_tipo_asiento(empresa, variable, obj, tipo_asiento)
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, "Centralizacion contable #{empresa.nombre}"
    Exportador::BaseXlsx.crear_encabezado(sheet, HEADERS_1, 0)
    Exportador::BaseXlsx.crear_encabezado(sheet, HEADERS_2, 1)
    Exportador::BaseXlsx.crear_encabezado(sheet, HEADERS_3, 2)

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    fecha_comprobante = I18n.l(date, format: "%d/%m/%Y")
    numero_documento = I18n.l(date, format: "%d%m%Y")
    mes = I18n.l(date, format: "%m")
    fecha_palabras = I18n.l(date, format: "%B %Y").upcase

    sub_diario = tipo_asiento == "CTS" ? "36" : "35"

    mes_tipo_asiento = "#{mes}#{TIPO_ASIENTO[tipo_asiento][0]}"
    glosa_principal = "#{TIPO_ASIENTO[tipo_asiento][1]} #{fecha_palabras}"

    agrupador = obj.group_by do |l|
      {
        cuenta_contable: search_account(l),
        anexo: search_agrupador(l),
        agrupador_cenco: search_cc(l),
        debe_haber: l.cuenta_custom_attrs["D/H"],
        deber_o_haber: l.deber_o_haber,
        glosa_detalle: glosa_por_afp(l),
      }
    end

    excel_data = agrupador.lazy.map do |k, v|
      [
        nil,
        sub_diario,
        mes_tipo_asiento,
        fecha_comprobante,
        "MN",
        glosa_principal,
        nil,
        "V",
        "S",
        nil,
        k[:cuenta_contable],
        k[:anexo],
        k[:agrupador_cenco],
        k[:debe_haber],
        v.sum(&:monto),
        nil,
        nil,
        "PL",
        numero_documento,
        fecha_comprobante,
        fecha_comprobante,
        nil,
        k[:glosa_detalle],
      ]
    end
    Exportador::BaseXlsx.escribir_celdas sheet, excel_data, offset: 3, number_format: '###.##'
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  private

    def search_agrupador(obj)
      ruc = obj.cuenta_custom_attrs["RUC"]
      return ruc if ruc.present?
      agrupador = obj.cuenta_custom_attrs["Agrupador"].to_s
      return unless agrupador.present?
      case agrupador.upcase
      when "DNI"
        obj.numero_documento
      when "CENCO"
        "0000"
      else
        ""
      end
    end

    def glosa_por_afp obj
      return afp_method(obj)&.custom_attrs&.dig("Descripcion Concepto") if obj.cuenta_custom_attrs["AFP"].to_s.casecmp('si').zero?
      obj.cuenta_custom_attrs["Descripcion Concepto"].presence || obj.glosa
    end

    def descartar_informativos(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_INFORMATIVOS.include?(l.item_code)
      end
    end
end

# EXAMPLE 42
#contact_america.rb


# frozen_string_literal: true

#
# clase para generar centralizacion contable personalizada para contact america
class Exportador::Contabilidad::Peru::Personalizadas::ContactAmerica < Exportador::Contabilidad::Peru::CentralizacionContable
  def initialize
    super()
    @extension = 'xlsx'
  end

  CABECERA = [
    'Origen',
    'Num.Voucher',
    'Fecha',
    'Cuenta',
    'Monto Debe',
    'Monto Haber',
    'Moneda S/D',
    'T.Cambio',
    'Doc',
    'Num.Doc',
    'Fec.Doc',
    'Fec.Ven',
    'codi. Prove/Client.',
    'C.Costo',
    'Presupuesto',
    'F.Efectivo',
    'Glosa',
    'Libro C/V/R',
    'Mto.Neto 1',
    'Mto.Neto 2',
    'Mto.Neto 3',
    'Mto.Neto 4',
    'Mto.Neto 5',
    'Mto.Neto 6',
    'Mto.Neto 7',
    'Mto.Neto 8',
    'Mto.IGV',
    'Ref.Doc',
    'Ref.Num.Doc',
    'Ref.Fecha',
    'D.Numero',
    'D.Fecha',
    'RUC',
    'R.Social',
    'Tipo, clie/prove/empleado',
    'Tip.Doc.Iden',
    'Medio de Pago',
    'Apellido 1',
    'Apellido 2',
    'Nombre',
    'T.Bien',
  ].freeze

  NO_CONTABILIZAR_INFORMATIVOS = [
    'buk_provision_bonificacion_gratificacion',
    'provision_bonificacion_extraordinaria_gratificacion_deber',
    'provision_bonificacion_extraordinaria_gratificacion_haber',
    'buk_provision_cts',
    'provision_cts_deber',
    'provision_cts_haber',
    'buk_provision_vacaciones',
    'provision_vacaciones_deber',
    'provision_vacaciones_haber',
    'buk_provision_gratificacion',
    'provision_gratificacion_deber',
    'provision_gratificacion_haber',
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    books = {}
    obj_contabilidad.group_by{|l| l.cuenta_custom_attrs&.dig('Tipo de asiento').presence || 'Otros'}.map do |k, obj|
      book = generate_book(empresa, variable, obj, k)
      books[k] = Exportador::Contabilidad::AccountingFile.new(contents: book, name: k)
    end
    books
  end

  def generate_book(empresa, variable, obj_contabilidad, nombre)
    return unless obj_contabilidad.present?

    obj_contabilidad = descartar_informativos(obj_contabilidad)

    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    Exportador::BaseXlsx.autofit sheet, [CABECERA]
    Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA, 0)

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    date_ddmmyyyy = I18n.l(date, format: '%d/%m/%Y')
    mes_anio = I18n.l(date, format: '%B %Y')
    asiento = "ASIENTO DE #{nombre} #{mes_anio}"

    obj_contabilidad = obj_contabilidad.group_by do |l|
      {
        cuenta_contable: cuenta_afp_por_attr(l),
        lado: l.deber_o_haber,
        centro_costo: search_cc(l),
        tipo_doc: get_tip_doc(l),
      }
    end

    data = obj_contabilidad.map do |k, v|
      [
        "11",
        "01",
        date_ddmmyyyy,
        k[:cuenta_contable],
        k[:lado] == 'C' ? v.sum(&:monto) : nil,
        k[:lado] == 'D' ? v.sum(&:monto) : nil,
        "S",
        "1",
        "00",
        nil,
        date_ddmmyyyy,
        date_ddmmyyyy,
        nil,
        k[:centro_costo],
        nil,
        nil,
        asiento.upcase,
        *Array.new(17),
        "5",
        k[:tipo_doc],
        "003",
      ]
    end

    Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 1, number_format: '#,##'
    Exportador::BaseXlsx.formatear_columna sheet, data, [4, 5], '####.00'
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end
  private
    def get_tip_doc l
      l.cuenta_custom_attrs["Mostrar RUT"] == "DNI" ? "1" : "4"
    end

    def descartar_informativos(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_INFORMATIVOS.include?(l.item_code)
      end
    end

    def cuenta_afp_por_attr(l)
      nombre_attr = search_name_afp(l.afp).to_s
      l.cuenta_custom_attrs&.dig("AFP").to_s.casecmp('si').zero? ? l.cuenta_custom_attrs&.dig(nombre_attr) : l.cuenta_contable
    end

    def search_name_afp obj
      case obj&.upcase
      when "PRIMA AFP"
        "AFP Prima"
      when "PROFUTURO AFP"
        "AFP Profuturo"
      else
        obj
      end
    end
end

# EXAMPLE 43
#oym.rb


# frozen_string_literal: true

#Centralización personalizada para empresa Oym Brands Perú
class Exportador::Contabilidad::Peru::Personalizadas::Oym < Exportador::Contabilidad
  include ContabilidadPeruHelper
  def initialize
    super()
    @extension = 'xls'
  end

  HEADER = [
    'Campo',
    'Sub Diario',
    'Número de Comprobante',
    'Fecha de Comprobante',
    'Código de Moneda',
    'Glosa Principal',
    'Tipo de Cambio',
    'Tipo de Conversión',
    'Flag de Conversión de Moneda',
    'Fecha Tipo de Cambio',
    'Cuenta Contable',
    'Código de Anexo',
    'Código de Centro de Costo',
    'Debe / Haber',
    'Importe Original',
    'Importe en Dólares',
    'Importe en Soles',
    'Tipo de Documento',
    'Número de Documento',
    'Fecha de Documento',
    'Fecha de Vencimiento',
    'Código de Area',
    'Glosa Detalle',
    'Código de Anexo Auxiliar',
    'Medio de Pago',
    'Tipo de Documento de Referencia',
    'Número de Documento Referencia',
    'Fecha Documento Referencia',
    'Nro Máq. Registradora Tipo Doc. Ref.',
    'Base Imponible Documento Referencia',
    'IGV Documento Provisión',
    'Tipo Referencia en estado MQ',
    'Número Serie Caja Registradora',
    'Fecha de Operación',
    'Tipo de Tasa',
    'Tasa Detracción/Percepción',
    'Importe Base Detracción/Percepción Dólares',
    'Importe Base Detracción/Percepción Soles',
    "Tipo Cambio para 'F'",
    'Importe de IGV sin derecho crédito fiscal',
    'Tasa IGV',
  ].freeze

  HEADER2 = [
    'Restricciones',
    'Ver T.G. 02',
    'Los dos primeros dígitos son el mes y los otros 4 siguientes un correlativo',
    '',
    'Ver T.G. 03',
    '',
    "Llenar solo si Tipo de Conversión es 'C'. Debe estar entre >=0 y <=9999.999999",
    "Solo: 'C'= Especial, 'M'=Compra, 'V'=Venta , 'F' De acuerdo a fecha",
    "Solo: 'S' = Si se convierte, 'N'= No se convierte",
    "Si Tipo de Conversión 'F'",
    'Debe existir en el Plan de Cuentas',
    'Si Cuenta Contable tiene seleccionado Tipo de Anexo, debe existir en la tabla de Anexos',
    'Si Cuenta Contable tiene habilitado C. Costo, Ver T.G. 05',
    "'D' ó 'H'",
    'Importe original de la cuenta contable. Obligatorio, debe estar entre >=0 y <=99999999999.99 ',
    "Importe de la Cuenta Contable en Dólares. Obligatorio si Flag de Conversión de Moneda esta en 'N', debe estar entre >=0 y <=99999999999.99 ",
    "Importe de la Cuenta Contable en Soles. Obligatorio si Flag de Conversión de Moneda esta en 'N', debe estra entre >=0 y <=99999999999.99 ",
    'Si Cuenta Contable tiene habilitado el Documento Referencia Ver T.G. 06',
    'Si Cuenta Contable tiene habilitado el Documento Referencia Incluye Serie y Número',
    'Si Cuenta Contable tiene habilitado el Documento Referencia',
    'Si Cuenta Contable tiene habilitada la Fecha de Vencimiento',
    'Si Cuenta Contable tiene habilitada el Area. Ver T.G. 26',
    '',
    'Si Cuenta Contable tiene seleccionado Tipo de Anexo Referencia',
    "Si Cuenta Contable tiene habilitado Tipo Medio Pago. Ver T.G. 'S1'",
    "Si Tipo de Documento es 'NA' ó 'ND' Ver T.G. 06",
    "Si Tipo de Documento es 'NC', 'NA' ó 'ND', incluye Serie y Número",
    "Si Tipo de Documento es 'NC', 'NA' ó 'ND'",
    "Si Tipo de Documento es 'NC', 'NA' ó 'ND'. Solo cuando el Tipo Documento de Referencia 'TK'",
    "Si Tipo de Documento es 'NC', 'NA' ó 'ND'",
    "Si Tipo de Documento es 'NC', 'NA' ó 'ND'",
    "Si la Cuenta Contable tiene Habilitado Documento Referencia 2 y Tipo de Documento es 'TK'",
    "Si la Cuenta Contable teien Habilitado Documento Referencia 2 y Tipo de Documento es 'TK'",
    "Si la Cuenta Contable tiene Habilitado Documento Referencia 2. Cuando Tipo de Documento es 'TK', consignar la fecha de emision del ticket",
    "Si la Cuenta Contable tiene configurada la Tasa: Si es '1' ver T.G. 28 y '2' ver T.G. 29",
    "Si la Cuenta Contable tiene conf. en Tasa: Si es '1' ver T.G. 28 y '2' ver T.G. 29. Debe estar entre >=0 y <=999.99",
    'Si la Cuenta Contable tiene configurada la Tasa. Debe ser el importe total del documento y estar entre >=0 y <=99999999999.99',
    'Si la Cuenta Contable tiene configurada la Tasa. Debe ser el importe total del documento y estar entre >=0 y <=99999999999.99',
    "Especificar solo si Tipo Conversión es 'F'. Se permite 'M' Compra y 'V' Venta.",
    'Especificar solo para comprobantes de compras con IGV sin derecho de crédito Fiscal. Se detalle solo en la cuenta 42xxxx',
    'Obligatorio para comprobantes de compras, valores validos 0,10,18.',
  ].freeze

  HEADER3 = [
    'Tamaño/Formato',
    '4 Caracteres',
    '6 Caracteres',
    'dd/mm/aaaa',
    '2 Caracteres',
    '40 Caracteres',
    'Numérico 11, 6',
    '1 Caracteres',
    '1 Caracteres',
    'dd/mm/aaaa',
    '12 Caracteres',
    '18 Caracteres',
    '6 Caracteres',
    '1 Carácter',
    'Numérico 14,2',
    'Numérico 14,2',
    'Numérico 14,2',
    '2 Caracteres',
    '20 Caracteres',
    'dd/mm/aaaa',
    'dd/mm/aaaa',
    '3 Caracteres',
    '30 Caracteres',
    '18 Caracteres',
    '8 Caracteres',
    '2 Caracteres',
    '20 Caracteres',
    'dd/mm/aaaa',
    '20 Caracteres',
    'Numérico 14,2 ',
    'Numérico 14,2',
    "'MQ'",
    '15 caracteres',
    'dd/mm/aaaa',
    '5 Caracteres',
    'Numérico 14,2',
    'Numérico 14,2',
    'Numérico 14,2',
    '1 Caracter',
    'Numérico 14,2',
    'Numérico 14,2',
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    obj_contabilidad_agrupado = obj_contabilidad.group_by{|l| l.cuenta_custom_attrs["Tipo de asiento"] || "Sin Tipo de asiento"}

    hashes = {}
    obj_contabilidad_agrupado.each do |k, v|
      libro = generate_centralizacion(empresa, variable, k, v)
      hashes["Libro_#{k}".to_sym] = Exportador::Contabilidad::AccountingFile.new(contents: libro, name_formatter: -> (name) {"#{k}-#{name}"})
    end
    hashes
  end

  def generate_centralizacion(empresa, variable, tipo_asiento, obj)
    book = Exportador::Base.crear_libro
    sheet = book.create_worksheet name: empresa.nombre
    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    mes = date.strftime('%m')
    mes_anno = date.strftime('%m/%Y')
    end_date = date.strftime('%d/%m/%Y')
    month_year = I18n.l(date, format: '%B %Y').upcase
    glosa = "#{tipo_asiento} #{month_year}"

    obj.select(&:haber?).each do |l|
      l.deber_o_haber = 'H'
    end

    sheet.row(0).concat HEADER
    sheet.row(1).concat HEADER2
    sheet.row(2).concat HEADER3

    agrupador = obj.group_by do |l|
      {
        account: account_prefix(l),
        deber_haber: l.deber_o_haber,
        codigo_anexo: codigo_anexo(l),
        cenco: search_cc(l),
      }
    end

    agrupador.each.with_index(1) do |(k, v), index|
      sheet.row(index + 2).push(
        nil,
        "35",
        "#{mes}#{index.to_s.rjust(4, '0')}",
        end_date,
        "MN",
        glosa,
        "1",
        "V",
        "S",
        end_date,
        k[:account],
        k[:codigo_anexo],
        k[:cenco],
        k[:deber_haber],
        v.sum(&:monto),
        "1.00",
        v.sum(&:monto),
        "PL",
        mes_anno,
        end_date,
        end_date,
        "060",
        glosa,
      )
    end
    Exportador::Base.autofit sheet
    Exportador::Base.cerrar_libro(book).contenido
  end
  private

    def codigo_anexo l
      search_account(l) if l.cuenta_custom_attrs["Codigo de Anexo"].to_s.casecmp("si").zero?
    end

    def account_prefix l
      l.cuenta_custom_attrs["Agrupador"] == "CENCO" ? "#{l.area_custom_attrs["Prefijo"]}#{search_account(l)}" : search_account(l)
    end
end

# EXAMPLE 44
#contabilidad_aom.rb


# frozen_string_literal: true

# Archivo de Centralizacion Personalizada para cliente Contabilidad Aom Perú
class Exportador::Contabilidad::Peru::Personalizadas::ContabilidadAom < Exportador::Contabilidad
  include ContabilidadPeruHelper
  def initialize
    super()
    @extension = 'xlsx'
  end

  HEADER = [
    'Origen',
    'Num.Voucher',
    'Fecha',
    'Cuenta',
    'Monto Debe',
    'Monto Haber',
    'Moneda S/D',
    'T.Cambio',
    'Doc',
    'Num.Doc',
    'Fec.Doc',
    'Fec.Ven',
    'Cod.Prov.Clie',
    'C.Costo',
    'Presupuesto',
    'F.Efectivo',
    'Glosa',
    'Libro C/V/H',
    'Mto.Neto 1',
    'Mto.Neto 2',
    'Mto.Neto 3',
    'Mto.Neto 4',
    'Mto.Neto 5',
    'Mto.Neto 6',
    'Mto.Neto 7',
    'Mto.Neto 8',
    '',
    'Mto.IGV',
    'Ref.Doc',
    'Ref.Num.Doc',
    'Ref.Fecha',
    'D.Numero',
    'D.Fecha',
    'RUC ',
    'R.Social',
    'Tipo',
    'Tip.Doc.Iden',
    'Medio de Pago',
    'Apellido 1',
    'Apellido 2',
    'Nombre',
    'T.Bien',
  ].freeze

  NO_CONTABILIZAR_INFORMATIVOS = [
    'sctr_pension',
    'buk_vida_ley',
    'sctr_salud',
    'vida_ley',
    'buk_provision_cts',
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    obj_contabilidad = descartar_informativos(obj_contabilidad)

    libros = {}
    obj_contabilidad_grupo = obj_contabilidad.group_by{|l| l.cuenta_custom_attrs['Tipo de Asiento'] || "SIN TIPO DE ASIENTO"}

    obj_contabilidad_grupo.each do |k, obj|
      libro = generate_doc_centralizacion(empresa, variable, obj, k)
      libros["Libro_#{k}".to_sym] = Exportador::Contabilidad::AccountingFile.new(contents: libro, name_formatter: -> (name) {"#{name} #{k}"})
    end
    libros
  end

  def generate_doc_centralizacion(empresa, variable, obj, tipo_asiento)
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, "Centralización Contable"
    Exportador::BaseXlsx.crear_encabezado(sheet, HEADER, 0)

    var_date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    date = var_date.strftime("%d/%m/%Y")
    month_year = I18n.l(var_date, format: '%B %Y').upcase
    mes_anno = var_date.strftime("%m%Y")
    anno = var_date.strftime("%Y")
    tipo_cambio = kpi_dolar(variable.id, empresa.id, 'tipo_de_cambio') || 1
    pago_1q = Date.parse(empresa.custom_attrs["Pago 1Q - Vac"]).strftime("%d/%m/%Y")
    ruc_empresa = empresa.rut.humanize
    glosa = "#{tipo_asiento} #{month_year}"

    agrupador = obj.group_by do |l|
      {
        origen: l.cuenta_custom_attrs['Origen'],
        num_voucher: l.cuenta_custom_attrs['Num.Voucher'],
        cuenta_contable: search_account(l),
        deber_haber: l.deber_o_haber,
        numero_documento: numero_documento(tipo_asiento, l, mes_anno, anno),
        fecha_documento: fecha_documento(l, date, pago_1q),
        fecha_vencimiento: fecha_vencimiento(l, date, tipo_asiento, empresa),
        codigo_cliente: codigo_cliente(ruc_empresa, l),
        centro_costo: search_cenco(l),
        presupuesto: l.cuenta_custom_attrs['Presupuesto'],
        tipo_dni: l.cuenta_custom_attrs['Agrupador'] == 'TOTAL' ? 6 : l.employee_custom_attrs['Tipo de DOI Sunat'],
      }
    end

    excel_data = agrupador.sort_by{|key, _value| key[:deber_haber]}.reverse.lazy.map do |k, v|
      [
        k[:origen],
        k[:num_voucher],
        date,
        k[:cuenta_contable],
        k[:deber_haber] == "D" ? v.sum(&:monto) : nil,
        k[:deber_haber] == "C" ? v.sum(&:monto) : nil,
        "S",
        tipo_cambio,
        "BP",
        k[:numero_documento],
        k[:fecha_documento],
        k[:fecha_vencimiento],
        k[:codigo_cliente],
        k[:centro_costo],
        k[:presupuesto],
        nil,
        glosa,
        *Array.new(16),
        k[:codigo_cliente],
        nil,
        nil,
        k[:tipo_dni],
        *Array.new(5),
      ]
    end
    Exportador::BaseXlsx.escribir_celdas sheet, excel_data, offset: 1
    Exportador::BaseXlsx.autofit sheet, [HEADER]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  private

    def fecha_documento  obj, date, pago_1q
      obj.cuenta_custom_attrs["Adelanto"].to_s.casecmp('si').zero? && obj.deber_o_haber == 'C' ? pago_1q : date
    end

    def codigo_cliente ruc_empresa, obj
      case obj.cuenta_custom_attrs["Agrupador"]
      when "DNI"
        obj.numero_documento
      when "TOTAL"
        ruc_empresa
      end
    end

    def numero_documento tipo_asiento, obj, mes_anno, anno
      case tipo_asiento
      when "PROVISION DE PLANILLA", "LIQUIDACIONES"
        mes_anno
      when "PROVISION DE VACACIONES"
        obj.deber_o_haber == "D" ? mes_anno : anno
      when "PROVISION DE GRATIFICACIONES"
        obj.deber_o_haber == "D" ? mes_anno : "#{obj.cuenta_custom_attrs["Periodo Gratificación"]}#{anno}"
      when "PROVISION DE CTS"
        obj.deber_o_haber == "D" ? mes_anno : obj.cuenta_custom_attrs["Periodo CTS"]
      end
    end

    def fecha_vencimiento obj, date, tipo_asiento, empresa
      if obj.deber_o_haber == "D"
        date
      else
        case tipo_asiento
        when "PROVISION DE CTS"
          Date.parse(empresa.custom_attrs['Fecha Pago CTS']).strftime('%d/%m/%Y')
        when "PROVISION DE GRATIFICACIONES"
          Date.parse(empresa.custom_attrs["Fecha Pago GRAT"]).strftime("%d/%m/%Y")
        else
          date
        end
      end
    end

    def descartar_informativos(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_INFORMATIVOS.include?(l.item_code)
      end
    end
end

# EXAMPLE 45
#siclo.rb


# frozen_string_literal: true

#
# clase para generar centralizacion contable personalizada para siclo
class Exportador::Contabilidad::Peru::Personalizadas::Siclo < Exportador::Contabilidad::Peru::CentralizacionContable
  include ContabilidadPeruHelper
  def initialize
    super()
    @extension = 'xlsx'
  end

  CABECERA = [
    'Account',
    'Debit',
    'Credit',
    'Line Memo',
    'Entity',
    'Department',
    'Class',
    'Location',
    'CONCEPTO',
  ].freeze

  def generate_doc(empresa, _variable, obj_contabilidad)
    return unless obj_contabilidad.present?
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []

    obj_contabilidad = obj_contabilidad.group_by{|l| l.cuenta_custom_attrs["Tipo de Asiento"].presence || empresa.nombre}
    obj_contabilidad.each do |asiento, obj_conta|
      generate_sheet(book, obj_conta, asiento)
    end

    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def generate_sheet(book, obj_contabilidad, asiento)
    sheet = Exportador::BaseXlsx.crear_hoja book, asiento
    Exportador::BaseXlsx.autofit sheet, [CABECERA]
    Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA, 0)

    data = obj_contabilidad.lazy.map do |l|
      [
        get_cuenta_by_plan_contable_dinamico(l, "job"),
        l.deber.presence || 0,
        l.haber.presence || 0,
        l.employee.apellidos_nombre,
        '19',
        l.job_custom_attrs['Department'],
        l.job_custom_attrs['Class'],
        l.origin.job.recinto&.code,
        l.nombre_cuenta,
      ]
    end

    Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 1
  end

  private

    def glosa_custom(l)
      l.nombre_cuenta == 'bonos' ? l.item_code : l.glosa
    end
end

# EXAMPLE 46
#crece_capital.rb


# frozen_string_literal: true

#
# clase para generar centralizacion contable personalizada para crece capital
class Exportador::Contabilidad::Peru::Personalizadas::CreceCapital < Exportador::Contabilidad::Peru::CentralizacionContable
  def initialize
    super()
    @extension = 'xlsx'
  end

  CABECERA = [
    'FI_NUM_SECU',
    'FI_NUM_ASIE',
    'FI_MES_PECO',
    'FI_ANO_PECO',
    'FI_COD_SUBD_CONT',
    'FI_COD_OFIC',
    'FI_COD_PLAN_CONT',
    'FI_COD_EMPR',
    'FD_FEC_ASIE',
    'FS_MON_ASIE',
    'FI_TIP_MOVI_CONT',
    'FS_COD_CNTA_CONT',
    'FI_ANO_PLCT',
    'FS_MON_REGI',
    'FS_COD_TIPO_ENTI',
    'FS_COD_ENTI',
    'FS_COD_TIPO_ANEX',
    'FS_COD_ANEX',
    'FS_COD_TIDO_SIST',
    'FS_NUM_DOCU',
    'FD_FEC_EMIS',
    'FD_FEC_VENC',
    'FS_DET_GLOS',
    'FS_COD_TICA',
    'FN_FAC_CAMB',
    'FN_FAC_CAMB_BASE',
    'FN_FAC_CAMB_DIAR',
    'FN_FAC_CAMO_EXPR',
    'FN_IMP_MONE_ORIG',
    'FN_IMP_MONA_PRIM',
    'FN_IMP_MOEX_PRIM',
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    books = {}
    obj_contabilidad.group_by{|l| l.cuenta_custom_attrs&.dig('Tipo de asiento').presence || 'Sin Tipo de asiento'}.each do |k, obj|
      book = generate_book(empresa, variable, obj, k)
      books[k] = Exportador::Contabilidad::AccountingFile.new(contents: book, name: "#{empresa.nombre} - #{k}")
    end
    books
  end

  def generate_book(empresa, variable, obj_contabilidad, nombre_asiento)
    return unless obj_contabilidad.present?

    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    Exportador::BaseXlsx.autofit sheet, [CABECERA]
    Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA, 0)

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    date_ddmmyyyy = I18n.l(date, format: '%d/%m/%Y')
    date_year = date.year.to_s
    date_month = date.month.to_s
    glosa_general = "#{nombre_asiento} #{I18n.l(date, format: '%B %Y')}".titleize
    tipo_cambio = kpi_dolar(variable.id, empresa.id, 'tipo_de_cambio_contable')

    obj_contabilidad = obj_contabilidad.group_by do |l|
      {
        cuenta_contable: search_account(l),
        lado: l.deber_o_haber,
        dni: search_numero_documento(l).presence || l.cuenta_custom_attrs&.dig('Agrupador'),
      }
    end

    data = obj_contabilidad.map.with_index(1) do |(k, v), index|
      [
        index.to_s,
        nil,
        date_month,
        date_year,
        '35',
        '1',
        '1',
        '1',
        date_ddmmyyyy,
        'SOL',
        k[:lado] == 'D' ? '1' : '2',
        k[:cuenta_contable],
        date_year,
        'SOL',
        'CC',
        k[:dni],
        'SI',
        'TR',
        nil,
        nil,
        nil,
        nil,
        glosa_general,
        '002',
        '0',
        '0',
        tipo_cambio,
        tipo_cambio,
        v.sum(&:monto),
        v.sum(&:monto),
        (v.sum(&:monto) / tipo_cambio).round(2),
      ]
    end

    Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 1, number_format: '#,##0.00'
    Exportador::BaseXlsx.formatear_columna sheet, data, [26, 27], '#,##0.000'
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end
end

# EXAMPLE 47
#klog.rb


#Clase para la centralizacion personaliza cliente Klog
class Exportador::Contabilidad::Peru::Personalizadas::Klog < Exportador::Contabilidad
  def initialize
    super()
    @extension = 'xlsx'
  end
  TITULOS = [
    "Campo",
    "Sub Diario",
    "Número de Comprobante",
    "Fecha de Comprobante",
    "Código de Moneda",
    "Glosa Principal",
    "Tipo de Cambio",
    "Tipo de Conversión",
    "Flag de Conversión de Moneda",
    "Fecha Tipo de Cambio",
    "Cuenta Contable",
    "Código de Anexo",
    "Código de Centro de Costo",
    "Debe / Haber",
    "Importe Original",
    "Importe en Dólares",
    "Importe en Soles",
    "Tipo de Documento",
    "Número de Documento",
    "Fecha de Documento",
    "Fecha de Vencimiento",
    "Código de Area",
    "Glosa Detalle",
    "Código de Anexo Auxiliar",
    "Medio de Pago",
    "Tipo de Documento de Referencia",
    "Número de Documento Referencia",
    "Fecha Documento Referencia",
    "Nro Máq. Registradora Tipo Doc. Ref.",
    "Base Imponible Documento Referencia",
    "IGV Documento Provisión",
    "Tipo Referencia en estado MQ",
    "Número Serie Caja Registradora",
    "Fecha de Operación",
    "Tipo de Tasa",
    "Tasa Detracción/Percepción",
    "Importe Base Detracción/Percepción Dólares",
    "Importe Base Detracción/Percepción Soles",
    "Tipo Cambio para 'F'",
    "Importe de IGV sin derecho crédito fiscal",
  ].freeze
  def generate_doc(_empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present? # retorna nil para no generar libro vacío
    # book
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, "PLANILLA"
    mes = variable.end_date.strftime('%m')
    mes_annio = variable.end_date.strftime('%m%Y')
    nro_doc = variable.end_date.strftime('%m%Y')
    fecha_exp = Time.zone.today.strftime("%d/%m/%Y")
    # variables
    Exportador::BaseXlsx.crear_encabezado(sheet, TITULOS, 0)
    resumen = obj_contabilidad.group_by do |o|
      agrupacion(o)
    end
    index = 0
    excel_data = resumen.map do |k, v|
      index += 1
      [
        index,
        "35",
        "#{mes}0001",
        fecha_exp,
        "MN",
        "#{k[:glosa]}#{mes_annio}",
        nil,
        "V",
        "S",
        nil,
        k[:cuenta_contable],
        k[:cod_concar],
        k[:centro_costo],
        k[:deber_o_haber] == "D" ? "D" : "H",
        v.sum(&:monto),
        nil,
        nil,
        k[:tipo_doc],
        nro_doc,
        fecha_exp,
        fecha_exp,
        nil,
        "#{k[:glosa]}#{mes_annio}",
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
      ]
    end
    Exportador::BaseXlsx.escribir_celdas sheet, excel_data, offset: 1, number_format: '#,##0'
    Exportador::BaseXlsx.autofit sheet, [TITULOS]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end
  private
    def agrupacion o
      if o.cuenta_custom_attrs&.dig("Agrupación") == "DNI"
        {
          glosa: o.cuenta_custom_attrs&.dig("Glosa principal"),
          cuenta_contable: search_account(o),
          cod_concar: o.employee_custom_attrs&.dig("Código Concar"),
          deber_o_haber: o.deber_o_haber,
          tipo_doc: o.tipo_doc,
          dni: o.numero_documento,
        }
      elsif o.cuenta_custom_attrs&.dig("Agrupación") == "CC"
        {
          glosa: o.cuenta_custom_attrs&.dig("Glosa principal"),
          cuenta_contable: o.cuenta_contable,
          centro_costo: o.centro_costo,
          deber_o_haber: o.deber_o_haber,
          tipo_doc: o.tipo_doc,
        }
      else
        {
          glosa: o.cuenta_custom_attrs&.dig("Glosa principal"),
          cuenta_contable: o.cuenta_contable,
          deber_o_haber: o.deber_o_haber,
          tipo_doc: o.tipo_doc,
        }
      end
    end
    def search_account o
      o.cuenta_custom_attrs&.dig(o.afp).presence || o.cuenta_contable
    end
end

# EXAMPLE 48
#besco.rb


# Archivo de Centralizacion Personalizada cliente Besco Perú
class Exportador::Contabilidad::Peru::Personalizadas::Besco < Exportador::Contabilidad
  def initialize
    super()
    @extension = 'xlsx'
  end

  HEADER = [
    "Fecha",
    "Asiento",
    "tipo de cuenta",
    "Cuenta que no es Contable",
    "Cuenta principal",
    "Dimension financiera",
    "Descripción",
    "Débito",
    "Crédito",
    "Tipo de cuenta de contrapartida",
    "Cuenta que no es contable de contrapartida", #10
    "Cuenta de Contrapartida",
    "Dimension Financiera de Compensacion",
    "Texto de transacción de contrapartida",
    "Divisa",
    "Cantidad",
    "Categoría",
    "Divisa de Ventas",
    "Precio de Ventas",
    "Propiedad de la linea",
    "Número de línea",
    "Cuenta",
    "Dimension.MainAccount",
    "Cuenta de contrapartida2",
    "Dimension.MainAccount3",
    "Perfil de contabilización", #Partida de control
    "ID de proyecto", #documento
    "Texto", #probablemente de aqui se aqui en adelante eliminar
    "Empresa",
    "Empresa de contrapartida",
    "Grupo de impuestos",
    "Tipo de cambio",
    "Grupo de impuestos de artículos",
    "Grupo de retenciones de impuestos",
    "Fecha de emisión",
    "Entrada de inversión",
    "Fecha de inversión",
  ].freeze

  NO_CONTABILIZAR_INFORMATIVOS = [
    "buk_provision_gratificacion",
    "buk_provision_vacaciones",
    "buk_provision_cts",
    "buk_provision_bonificacion_gratificacion",
  ].freeze

  DIMENSIONES = [
    'proyecto',
    'proveedor',
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    obj_conta = descartar_informativos(obj_contabilidad)

    contrapartida = empresa.custom_attrs&.dig("Cuenta contrapartida")
    document_date = variable.end_date.latest_business_day(Location.country(empresa.country_namespace)).strftime('%Y-%m-%d')
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    obj_conta.group_by{|o| tipo(o)}.each do |nombre, group|
      accounts = sanitize(group, empresa)
      sheet = Exportador::BaseXlsx.crear_hoja book, nombre
      Exportador::BaseXlsx.crear_encabezado(sheet, HEADER, 0)
      excel_data = accounts.each_with_index.map do |(k, v), index|
        add_excel_row(k, v, index + 1, contrapartida, document_date)
      end
      Exportador::BaseXlsx.escribir_celdas sheet, excel_data, offset: 1, number_format: "###0.00"
      Exportador::BaseXlsx.autofit sheet, [HEADER]
    end
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def sanitize group, empresa
    group.group_by do |g|
      {
        descripcion: search_description(g),
        cuenta: search_account(g),
        cuenta_tipo: search_account_type(g),
        deber_o_haber: g.deber_o_haber,
        dimension: search_dimension(g),
        categoria_proyecto: search_project_category(g),
        id_proyecto: search_project_id(g),
        texto: g.cuenta_custom_attrs&.dig("Text"),
        posting_profile: search_posting_profile(g),
        grupo_de_impuestos: search_grupo_impuestos(g),
        search_cuenta_no_contable: search_cuenta_no_contable(g),
        search_cuenta_principal: search_cuenta_principal(g),
        search_prop_ventas: search_prop_ventas(g),
        search_ventas: search_ventas(g),
        cuenta_contrapartida2: empresa.custom_attrs&.dig("Cuenta contrapartida 2"),
        empresa: empresa.custom_attrs&.dig("Empresa Centralizacion"),
        empresa_contrapartida: empresa.custom_attrs&.dig("Empresa de Contrapartida Centralizacion"),
      }
    end
  end

  def add_excel_row k, v, index, contrapartida, document_date
    [
      document_date,
      "BUK#{index.to_s.rjust(7, "0")}",
      k[:cuenta_tipo],
      k[:search_cuenta_no_contable],
      k[:search_cuenta_principal],
      k[:dimension],
      k[:descripcion],
      k[:deber_o_haber] == "D" ? v.sum(&:monto) : nil,
      k[:deber_o_haber] == "C" ? v.sum(&:monto) : nil,
      "Contabilidad",
      nil,
      contrapartida,
      nil,
      "ASIENTO NOMINA",
      "PEN",
      0.to_s,
      k[:categoria_proyecto],
      k[:search_ventas],
      0.to_s,
      k[:search_prop_ventas],
      index.to_s,
      k[:cuenta],
      nil,
      k[:cuenta_contrapartida2],
      nil,
      k[:posting_profile],
      k[:id_proyecto],
      k[:texto], #Lo mas probable que eliminar
      k[:empresa],
      k[:empresa_contrapartida],
      k[:grupo_de_impuestos],
      1,
      nil,
      nil,
      nil,
      "No",
      nil,
    ]
  end

  def search_account_type g
    if g.regimen_ria.present?
      g.cuenta_custom_attrs&.dig("Account Type RIA")
    elsif g.cuenta_custom_attrs&.dig("Account Type")&.parameterize == "proyecto" && g.centro_costo_custom_attrs&.dig("Tipo de proyecto")&.parameterize == "legado"
      "Contabilidad"
    else
      g.cuenta_custom_attrs&.dig("Account Type")
    end
  end

  def search_grupo_impuestos g
    search_account_type(g)&.parameterize == "proveedor" ? "GRAL" : nil
  end

  def search_project_id g
    search_account_type(g)&.parameterize == "proyecto" ? g.centro_costo : nil
  end

  def search_dimension g
    dimension = search_account_type(g).to_s.parameterize
    DIMENSIONES.include?(dimension) ? g.centro_costo_custom_attrs&.dig("Codigo Largo") : nil
  end

  def search_account g
    codigo_largo = g.centro_costo_custom_attrs&.dig("Codigo Largo")&.presence
    codigo_largo = codigo_largo&.slice(0..-2)
    case search_account_type(g)&.parameterize
    when "contabilidad"
      "#{g.cuenta_contable}-#{codigo_largo}"
    when "proveedor"
      g.cuenta_custom_attrs&.dig("Numero contable centralizado")&.presence || g.ruc_afp
    when "proyecto"
      if g.centro_costo_custom_attrs&.dig("Tipo de proyecto")&.parameterize == "legado"
        case g.area_custom_attrs&.dig("Detalle Cuenta Contable")&.parameterize
        when "detalle"
          "#{g.cuenta_contable}-#{codigo_largo}"
        when "proyecto"
          cuenta_contable = g.cuenta_custom_attrs&.dig("Numero de cuenta legado")
          "#{cuenta_contable}-#{codigo_largo}"
        end
      else
        g.centro_costo_custom_attrs&.dig("Project ID")
      end
    end
  end.presence || g.cuenta_contable

  def search_posting_profile g
    return if search_account_type(g) != "Proveedor"
    if g.item_code.to_s.match?("afp")
      nombre_afp = g.afp.to_s.upcase.sub("AFP", "").strip.first(3)
      "AFP#{nombre_afp}XPAG"
    else
      g.cuenta_custom_attrs&.dig("Posting Profile")
    end
  end

  def search_description g
    case search_account_type(g)&.parameterize
    when "contabilidad"
      g.cuenta_custom_attrs&.dig("Descripción")
    when "proveedor"
      g.cuenta_custom_attrs&.dig("Descripción")
    when "proyecto"
      case g.area_custom_attrs&.dig("Detalle Cuenta Contable")&.parameterize
      when "detalle"
        g.cuenta_custom_attrs&.dig("Descripción")
      when "proyecto"
        g.centro_costo_custom_attrs&.dig("Descripción")
      else
        g.glosa
      end
    else
      g.glosa
    end
  end

  def search_project_category g
    cuentas = ["contabilidad", "proveedor"]
    return if cuentas.include?(search_account_type(g)&.parameterize)
    if g.cuenta_custom_attrs&.dig("Account Type")&.parameterize == "proyecto"
      if g.centro_costo_custom_attrs&.dig("Tipo de proyecto")&.parameterize == "legado"
        return if ["detalle", "proyecto"].include?(g.area_custom_attrs&.dig("Detalle Cuenta Contable")&.parameterize)
      end
      case g.area_custom_attrs&.dig("Detalle Cuenta Contable")&.parameterize
      when "detalle"
        g.cuenta_custom_attrs&.dig("Project Category CC")
      when "proyecto"
        g.area_custom_attrs&.dig("Project Category Area")
      end
    end
  end


  def tipo object
    return "Practicantes" if object.nombre_cuenta == "sueldo_liquido" && object.origin&.job&.contrato_practica?
    object.cuenta_custom_attrs&.dig("Tipo de Asiento").presence || "Sin Definir"
  end

  def search_cuenta_no_contable g
    codigo_largo = g.centro_costo_custom_attrs&.dig("Codigo Largo")
    case search_account_type(g)&.parameterize
    when "contabilidad"
      nil
    when "proveedor"
      g.cuenta_custom_attrs&.dig("Numero contable centralizado")&.presence || g.ruc_afp
    when "proyecto"
      if g.centro_costo_custom_attrs&.dig("Tipo de proyecto")&.parameterize == "legado"
        case g.area_custom_attrs&.dig("Detalle Cuenta Contable")&.parameterize
        when "detalle"
          "#{g.cuenta_contable}-#{codigo_largo}"
        when "proyecto"
          cuenta_contable = g.cuenta_custom_attrs&.dig("Numero de cuenta legado")
          "#{cuenta_contable}-#{codigo_largo}"
        end
      else
        g.centro_costo_custom_attrs&.dig("Project ID")
      end
    end
  end

  def search_cuenta_principal g
    if g.regimen_ria&.present? && g.cuenta_custom_attrs&.dig("Numero contable RIA")&.present?
      g.cuenta_custom_attrs&.dig("Numero contable RIA")
    else
      case search_account_type(g)&.parameterize
      when "contabilidad"
        g.cuenta_contable
      when "proyecto"
        if g.centro_costo_custom_attrs&.dig("Tipo de proyecto")&.parameterize == "legado"
          g.cuenta_contable
        end
      end
    end
  end

  def search_prop_ventas g
    search_account_type(g)&.parameterize == "proyecto" ? "NO_FACTURA" : nil
  end

  def search_ventas g
    search_account_type(g)&.parameterize == "proyecto" ? "PEN" : nil
  end

  def descartar_informativos(obj)
    obj.reject do |l|
      NO_CONTABILIZAR_INFORMATIVOS.include?(l.item_code)
    end
  end

end

# EXAMPLE 49
#idea2_group_sac.rb


#Clase para la centralizacion personaliza cliente Idea2GroupSac
class Exportador::Contabilidad::Peru::Personalizadas::Idea2GroupSac < Exportador::Contabilidad
  def initialize
    super()
    @extension = 'xlsx'
  end
  def generate_doc(_empresa, _variable, obj_contabilidad)
    return unless obj_contabilidad.present? # retorna nil para no generar libro vacío
    # book
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, "PLANILLA"
    # variables
    titulos = [
      "NUMERO DE DOCUMENTO",
      "APELLIDOS",
      "NOMBRES",
      "CARGO",
      "CUENTA CONTABLE",
      "VALOR DEBE",
      "VALOR HABER",
      "CENTRO COSTOS",
      "DESCRIPCIÓN CONCEPTO",
    ]
    Exportador::BaseXlsx.crear_encabezado(sheet, titulos, 0)
    resumen = obj_contabilidad.group_by do |o|
      validador = o.cuenta_custom_attrs&.dig("Distribucion")&.parameterize == "detalle"
      {
        numero_documento: validador ? o.numero_documento&.humanize : nil,
        apellido: validador ? o.last_name : nil,
        nombres: validador ? o.first_name : nil,
        cargo: validador ? o.role_name : nil,
        cuenta_contable: search_account(o),
        deber_o_haber: o.deber_o_haber,
        centro_costo: search_cenco(o),
        glosa: search_glosa(o),
      }
    end
    excel_data = resumen.map do |k, v|
      [
        k[:numero_documento],
        k[:apellido],
        k[:nombres],
        k[:cargo],
        k[:cuenta_contable],
        k[:deber_o_haber] == "D" ? v.sum(&:monto) : 0,
        k[:deber_o_haber] == "C" ? v.sum(&:monto) : 0,
        k[:centro_costo],
        k[:glosa],
      ]
    end
    Exportador::BaseXlsx.escribir_celdas sheet, excel_data, offset: 1, number_format: '#,##0'
    Exportador::BaseXlsx.autofit sheet, [titulos]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  private
    def search_account object
      object.cuenta_custom_attrs&.dig(object.afp).presence || object.cuenta_contable
    end

    def search_glosa object
      object.nombre_cuenta == "afp" ? object.afp : object.glosa
    end

    def search_cenco object
      object.cuenta_custom_attrs&.dig("Distribucion")&.parameterize == "cencos" ? object.centro_costo : nil
    end
end

# EXAMPLE 50
#rosen.rb


# frozen_string_literal: true

#Centralización personalizada para empresa Rosen
class Exportador::Contabilidad::Peru::Personalizadas::Rosen < Exportador::Contabilidad
  include ContabilidadPeruHelper
  def initialize
    super()
    @extension = 'xls'
  end

  TITULOS = [
    'Cuenta de mayor/Código SN',
    'Cuenta de mayor/Nombre SN',
    'Cuenta asociada',
    'Débito',
    'Crédito',
    'Débito (MS)',
    'Crédito (MS)',
    'Norma de reparto',
    'Comentarios',
    'Referencia 1',
    'Referencia 2',
    'Referencia 3',
  ].freeze

  NO_CONTABILIZAR_INFORMATIVOS = [
    "buk_provision_vacaciones",
    "buk_provision_gratificacion",
    "buk_provision_cts",
    "buk_provision_bonificacion_gratificacion",
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    mm_yyyy = I18n.l(date, format: '%B %Y')
    obj_contabilidad = descartar_informativos(obj_contabilidad)

    obj_contabilidad_agrupado = obj_contabilidad.group_by{|l| l.cuenta_custom_attrs["Tipo de asiento"] || "Sin_Asiento"}

    hashes = {}
    obj_contabilidad_agrupado.each do |k, v|
      tipo_asiento_month_year = "#{k} #{mm_yyyy}"
      libro = generate_centralizacion(empresa, variable, v, tipo_asiento_month_year)
      hashes["Libro_#{k}".to_sym] = Exportador::Contabilidad::AccountingFile.new(contents: libro, name_formatter: -> (name) {"#{k}-#{name}"})
    end
    hashes
  end

  def generate_centralizacion(empresa, variable, obj_contabilidad, tipo_asiento_month_year)
    book = Exportador::Base.crear_libro
    sheet = book.create_worksheet name: empresa.nombre
    tipo_cambio = kpi_dolar(variable.id, empresa.id) || 1

    sheet.row(0).concat TITULOS

    agrupador = obj_contabilidad.group_by do |l|
      {
        cuenta: search_account(l),
        cuenta_mayor_nombre: search_name_afp(l),
        deber_o_haber: l.deber_o_haber,
        cenco: get_cencos(l),
        ref_nombre: get_lastname(l),
      }
    end

    agrupador.each_with_index do |(k, v), index|
      sheet.row(index + 1).push(
        k[:cuenta],
        k[:cuenta_mayor_nombre],
        k[:cuenta],
        k[:deber_o_haber] == "D" ? v.sum(&:monto) : nil,
        k[:deber_o_haber] == "C" ? v.sum(&:monto) : nil,
        k[:deber_o_haber] == "D" ? (v.sum(&:monto) / tipo_cambio).round(2) : nil,
        k[:deber_o_haber] == "C" ? (v.sum(&:monto) / tipo_cambio).round(2) : nil,
        k[:cenco],
        tipo_asiento_month_year,
        k[:ref_nombre],
      )
    end
    Exportador::Base.autofit sheet
    Exportador::Base.cerrar_libro(book).contenido
  end
  private
    def get_lastname obj
      "#{obj.last_name} #{obj.second_last_name} #{obj.first_name}" if obj.cuenta_custom_attrs["Referencia 1"] == "SI"
    end

    def search_name_afp obj
      obj.cuenta_custom_attrs["AFP"].to_s.upcase.squish == "SI" ? afp_method(obj)&.custom_attrs&.dig('Nombre de la cuenta') : obj.cuenta_custom_attrs['Nombre de la cuenta']
    end

    def get_cencos obj
      obj.centro_costo_custom_attrs['Objeto'] if obj.cuenta_custom_attrs['Agrupador'] == 'CENCO'
    end

    def descartar_informativos(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_INFORMATIVOS.include?(l.item_code)
      end
    end
end

# EXAMPLE 51
#conexa.rb


# frozen_string_literal: true

#
# clase para generar centralizacion contable personalizada para conexa
class Exportador::Contabilidad::Peru::Personalizadas::Conexa < Exportador::Contabilidad::Peru::CentralizacionContable
  def initialize
    super()
    @extension = 'xlsx'
  end

  CABECERA_1 = [
    "Campo",
    "Sub Diario",
    "Número de Comprobante",
    "Fecha de Comprobante",
    "Código de Moneda",
    "Glosa Principal",
    "Tipo de Cambio",
    "Tipo de Conversión",
    "Flag de Conversión de Moneda",
    "Fecha Tipo de Cambio",
    "Cuenta Contable",
    "Código de Anexo",
    "Código de Centro de Costo",
    "Debe / Haber",
    "Importe Original",
    "Importe en Dólares",
    "Importe en Soles",
    "Tipo de Documento",
    "Número de Documento",
    "Fecha de Documento",
    "Fecha de Vencimiento",
    "Código de Area",
    "Glosa Detalle",
    "Código de Anexo Auxiliar",
    "Medio de Pago",
    "Tipo de Documento de Referencia",
    "Número de Documento Referencia",
    "Fecha Documento Referencia",
    "Nro Máq. Registradora Tipo Doc. Ref.",
    "Base Imponible Documento Referencia",
    "IGV Documento Provisión",
    "Tipo Referencia en estado MQ",
    "Número Serie Caja Registradora",
    "Fecha de Operación",
    "Tipo de Tasa",
    "Tasa Detracción/Percepción",
    "Importe Base Detracción/Percepción Dólares",
    "Importe Base Detracción/Percepción Soles",
    "Tipo Cambio para 'F'",
    "Importe de IGV sin derecho crédito fiscal",
    "Tasa IGV",
  ].freeze

  CABECERA_2 = [
    "Restricciones",
    "Ver T.G. 02",
    "Los dos primeros dígitos son el mes y los otros 4 siguientes un correlativo",
    "",
    "Ver T.G. 03",
    "",
    "Llenar  solo si Tipo de Conversión es 'C'. Debe estar entre >=0 y <=9999.999999",
    "Solo: 'C'= Especial, 'M'=Compra, 'V'=Venta , 'F' De acuerdo a fecha",
    "Solo: 'S' = Si se convierte, 'N'= No se convierte",
    "Si  Tipo de Conversión 'F'",
    "Debe existir en el Plan de Cuentas",
    "Si Cuenta Contable tiene seleccionado Tipo de Anexo, debe existir en la tabla de Anexos",
    "Si Cuenta Contable tiene habilitado C. Costo, Ver T.G. 05",
    "'D' ó 'H'",
    "Importe original de la cuenta contable. Obligatorio, debe estar entre >=0 y <=99999999999.99",
    "Importe de la Cuenta Contable en Dólares. Obligatorio si Flag de Conversión de Moneda esta en 'N', debe estar entre >=0 y <=99999999999.99",
    "Importe de la Cuenta Contable en Soles. Obligatorio si Flag de Conversión de Moneda esta en 'N', debe estra entre >=0 y <=99999999999.99",
    "Si Cuenta Contable tiene habilitado el Documento Referencia Ver T.G. 06",
    "Si Cuenta Contable tiene habilitado el Documento Referencia Incluye Serie y Número",
    "Si Cuenta Contable tiene habilitado el Documento Referencia",
    "Si Cuenta Contable tiene habilitada la Fecha de Vencimiento",
    "Si Cuenta Contable tiene habilitada el Area. Ver T.G. 26",
    "",
    "Si Cuenta Contable tiene seleccionado Tipo de Anexo Referencia",
    "Si Cuenta Contable tiene habilitado Tipo Medio Pago. Ver T.G. 'S1'",
    "Si Tipo de Documento es 'NA' ó 'ND' Ver T.G. 06",
    "Si Tipo de Documento es 'NC', 'NA' ó 'ND', incluye Serie y Número",
    "Si Tipo de Documento es 'NC', 'NA' ó 'ND'",
    "Si Tipo de Documento es 'NC', 'NA' ó 'ND'. Solo cuando el Tipo Documento de Referencia 'TK'",
    "Si Tipo de Documento es 'NC', 'NA' ó 'ND'",
    "Si Tipo de Documento es 'NC', 'NA' ó 'ND'",
    "Si la Cuenta Contable tiene Habilitado Documento Referencia 2 y  Tipo de Documento es 'TK'",
    "Si la Cuenta Contable teien Habilitado Documento Referencia 2 y  Tipo de Documento es 'TK'",
    "Si la Cuenta Contable tiene Habilitado Documento Referencia 2. Cuando Tipo de Documento es 'TK', consignar la fecha de emision del ticket",
    "Si la Cuenta Contable tiene configurada la Tasa:  Si es '1' ver T.G. 28 y '2' ver T.G. 29",
    "Si la Cuenta Contable tiene conf. en Tasa:  Si es '1' ver T.G. 28 y '2' ver T.G. 29. Debe estar entre >=0 y <=999.99",
    "Si la Cuenta Contable tiene configurada la Tasa. Debe ser el importe total del documento y estar entre >=0 y <=99999999999.99",
    "Si la Cuenta Contable tiene configurada la Tasa. Debe ser el importe total del documento y estar entre >=0 y <=99999999999.99",
    "Especificar solo si Tipo Conversión es 'F'. Se permite 'M' Compra y 'V' Venta.",
    "Especificar solo para comprobantes de compras con IGV sin derecho de crédito Fiscal. Se detalle solo en la cuenta 42xxxx",
    "Obligatorio para comprobantes de compras, valores validos 0,10,18.",
  ].freeze

  CABECERA_3 = [
    "Tamaño/Formato",
    "4 Caracteres",
    "6 Caracteres",
    "dd/mm/aaaa",
    "2 Caracteres",
    "40 Caracteres",
    "Numérico 11, 6",
    "1 Caracteres",
    "1 Caracteres",
    "dd/mm/aaaa",
    "12 Caracteres",
    "18 Caracteres",
    "",
    "1 Carácter",
    "Numérico 14,2",
    "Numérico 14,2",
    "Numérico 14,2",
    "2 Caracteres",
    "20 Caracteres",
    "dd/mm/aaaa",
    "dd/mm/aaaa",
    "3 Caracteres",
    "30 Caracteres",
    "18 Caracteres",
    "8 Caracteres",
    "2 Caracteres",
    "20 Caracteres",
    "dd/mm/aaaa",
    "20 Caracteres",
    "Numérico 14,2",
    "Numérico 14,2",
    "'MQ'",
    "15 caracteres",
    "dd/mm/aaaa",
    "5 Caracteres",
    "Numérico 14,2",
    "Numérico 14,2",
    "Numérico 14,2",
    "1 Caracter",
    "Numérico 14,2",
    "Numérico 14,2",
  ].freeze

  NO_CONTABILIZAR_INFORMATIVOS = [
    "provision_bonificacion_extraordinaria_gratificacion_deber",
    "provision_bonificacion_extraordinaria_gratificacion_haber",
    "provision_gratificacion_deber",
    "provision_gratificacion_haber",
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    Exportador::BaseXlsx.crear_encabezado sheet, CABECERA_1, 0
    Exportador::BaseXlsx.crear_encabezado sheet, CABECERA_2, 1
    Exportador::BaseXlsx.crear_encabezado sheet, CABECERA_3, 2
    obj_contabilidad = descartar_informativos(obj_contabilidad)

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)

    date_month_year = I18n.l(date, format: '%b %Y').upcase
    date_ddmmyyyy = I18n.l(date, format: '%d/%m/%Y')
    date_mmyyyy = I18n.l(date, format: '%m-%Y')

    num_documento = "PL #{date_mmyyyy}"
    kpi = kpi_dolar(variable.id, empresa.id).presence

    agrupado = obj_contabilidad.group_by do |l|
      {
        subdiario: l.cuenta_custom_attrs["Sub Diario"],
        num_comprobante: l.cuenta_custom_attrs["Número de Comprobante"],
        glosa_general: "#{l.cuenta_custom_attrs["Tipo de asiento"].upcase} MES DE #{date_month_year}",
        conversion: l.cuenta_custom_attrs["Tipo de Conversión"],
        flag_conversion: l.cuenta_custom_attrs["Flag de Conversión de Moneda"],
        cuenta_contable: search_account(l),
        cod_anexo: cod_anexo(l),
        centro_costo: search_cenco(l),
        debe_haber: l.deber_o_haber,
      }
    end

    data = agrupado.map do |k, v|
      [
        nil,
        k[:subdiario],
        k[:num_comprobante],
        date_ddmmyyyy,
        'MN',
        k[:glosa_general],
        kpi,
        k[:conversion],
        k[:flag_conversion],
        nil,
        k[:cuenta_contable],
        k[:cod_anexo],
        k[:centro_costo],
        k[:debe_haber] == 'C' ? 'H' : 'D',
        v.sum(&:monto),
        nil,
        kpi.present? ? (v.sum(&:monto) * kpi) : nil,
        nil,
        "PL",
        num_documento,
        date_ddmmyyyy,
        nil,
        nil,
        k[:glosa_general],
      ]
    end

    Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 3, number_format: '#,##0.00'
    Exportador::BaseXlsx.autofit sheet, [CABECERA_1]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  private

    def cod_anexo obj
      case obj.cuenta_custom_attrs["Agrupador"].to_s.upcase
      when 'AFP'
        afp_method(obj)&.nombre
      when 'DNI'
        obj.numero_documento
      end
    end

    def descartar_informativos(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_INFORMATIVOS.include?(l.nombre_cuenta)
      end
    end

end

# EXAMPLE 52
#grupo_cintac.rb


# frozen_string_literal: true

#
# Clase para generar contabilidad personalizad de Grupo Cintac
class Exportador::Contabilidad::Peru::Personalizadas::GrupoCintac < Exportador::Contabilidad
  include HelperContabilidad

  def initialize
    super()
    @extension = 'xlsx'
  end

  CABECERA_1 = ['ID Cabecera',
                'Doc Correlativo',
                'Sociedad',
                'Fecha de documento',
                'Fecha de contabilización',
                'Clase de documento',
                'Periodo',
                'Moneda',
                'Tipo de cambio Directo',
                'Tipo de cambio Indirecto',
                'Referencia',
                'Texto de cabecera',
                'Calculo de Impto',
                'Normas de Presentacion de Cuenta',
                'Fecha Conversion',].freeze

  CABECERA_2 = ['ID Posición',
                'Doc Correlativo',
                'Debe/Haber (S/H)',
                'Clase de cuenta (S,D,K)',
                'Cuenta',
                'Indicador CME',
                'Importe en moneda de documento',
                'Indicador IVA',
                'Centro de costo',
                'Centro de beneficio',
                'Orden CO',
                'Numero de material',
                'Asignación',
                'Texto de posición',
                'Moneda de pago',
                'Importe en moneda de pago',
                'Referencia de pago',
                'Via de pago',
                'Condiciones de Pago',
                'Fecha de vencimiento',
                'Clave de referencia 1',
                'Clave de referencia 2',
                'Clave de referencia  3',
                'Cuenta de mayor',
                'Receptor Alt.Pago',
                'Elemento PEP',
                'Banco Propio',
                'ID Banco',].freeze

  NO_CONTABILIZAR_INFORMATIVOS = [
    'buk_provision_vacaciones',
    'buk_provision_gratificacion',
    'buk_provision_bonificacion_gratificacion',
    'buk_provision_cts',
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    fecha = I18n.l(date, format: "%d.%m.%Y")
    mes = I18n.l(date, format: "%-m").upcase
    year_month = I18n.l(date, format: "%Y.%m")

    obj_contabilidad = descartar_informativos(obj_contabilidad)

    grouped = obj_contabilidad.group_by{ |l| l.cuenta_custom_attrs['Tipo de Asiento'] || '' }

    grouped.map do |k, obj|
      tipo_asiento = k
      libro = generar_centralizacion(empresa, obj, fecha, mes, tipo_asiento, year_month)
      ["Libro_#{k}", Exportador::Contabilidad::AccountingFile.new(contents: libro, name_formatter: -> (name) {"#{name} - Interfaz Contable #{k.presence || 'Sin Clasificar'}"})]
    end.to_h
  end

  def generar_centralizacion(empresa, obj_contabilidad, fecha, mes, tipo_asiento, year_month)
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre

    cabecera_3 = [
      "H",
      "1",
      empresa.custom_attrs["Nombre Contabilidad"],
      fecha,
      fecha,
      "SA",
      mes,
      "PEN",
      nil,
      nil,
      "#{tipo_asiento} #{year_month}",
      "#{tipo_asiento} #{year_month}",
      empresa.custom_attrs["Glosa_Empresa"],
    ]
    Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA_1, 0)
    Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA_2, 1)
    Exportador::BaseXlsx.crear_encabezado(sheet, cabecera_3, 2)

    agrupado = obj_contabilidad.group_by do |obj|
      cambio, pep = get_centro_pep(obj)
      {
        deber_haber: obj.cuenta_custom_attrs["S/H"],
        clase_cuenta: obj.cuenta_custom_attrs["Clase de Cuenta"],
        cuenta_contable: get_cuenta_contable(obj),
        cambio_directo: cambio,
        elemento_pep: pep,
        cme: obj.cuenta_custom_attrs["Indicador CME"],
        descripcion_plan_contable: descripcion_plan_contable(obj),
        dni: dni(obj),
      }
    end

    excel_data = agrupado.lazy.map do |k, v|
      [
        "L",
        "1",
        k[:deber_haber],
        k[:clase_cuenta],
        k[:cuenta_contable],
        k[:cme],
        v.sum(&:monto),
        nil,
        k[:cambio_directo],
        *Array.new(3),
        "#{tipo_asiento} #{year_month}",
        k[:descripcion_plan_contable],
        * Array.new(11),
        k[:elemento_pep],
      ]
    end
    Exportador::BaseXlsx.escribir_celdas sheet, excel_data, offset: 3
    Exportador::BaseXlsx.autofit sheet, [CABECERA_1]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end


  private

    def get_centro_pep l
      return unless l.cuenta_custom_attrs["Agrupador"] == "CECO"
      case l.area_custom_attrs["Contabilizar"]
      when "CECO"
        [l.centro_costo, nil]
      when "PEP"
        [nil, l.centro_costo]
      end
    end

    def get_cuenta_contable obj
      return obj.employee_custom_attrs["BP SAP"] if obj.cuenta_custom_attrs["BP SAP"].to_s.casecmp("si").zero?
      obj.job_custom_attrs["Plan Contable"].to_s.parameterize == "ria" ? obj.cuenta_custom_attrs["RIA"] : obj.cuenta_contable
    end

    def descartar_informativos(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_INFORMATIVOS.include?(l.item_code)
      end
    end

    def descripcion_plan_contable l
      l.job_custom_attrs["Plan Contable"] == "Número" ? l.cuenta_customgit_attrs["Descripción"] : l.cuenta_custom_attrs["Descripción RIA"]
    end

    def dni l
      l.numero_documento if l.cuenta_custom_attrs["Agrupador"] == "DNI"
    end
end

# EXAMPLE 53
#terceriza_peru.rb


#Clase para la centralizacion personaliza cliente 3eriza
class Exportador::Contabilidad::Peru::Personalizadas::TercerizaPeru < Exportador::Contabilidad
  def initialize
    super()
    @extension = 'xlsx'
  end

  TITULOS = ['ID',
             'line_ids/account_id/id',
             'line_ids/partner_id/id',
             'Apuntes Contables/Cuenta Analitica/Id Externo',
             'line_ids/name',
             'line_ids/amount_currency',
             'line_ids/currency_id/id',
             'line_ids/debit',
             'line_ids/credit',
             'Cod. Cta. Contable',
             'Cuenta Contable',
             'Apellidos Nombres',
             'Codigo Costo',
             'Nombre Costo',].freeze

  def generate_doc(_empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    remuneraciones = excel_data(variable, obj_contabilidad.select{|l| l.cuenta_custom_attrs&.dig("Provision") == 'Remuneraciones'})
    bonos = excel_data(variable, obj_contabilidad.select{|l| l.cuenta_custom_attrs&.dig("Provision") == 'BBSS'})
    liquidaciones = excel_data(variable, obj_contabilidad.select{|l| l.cuenta_custom_attrs&.dig("Provision") == 'Liquidaciones'})
    {
      remuneraciones: Exportador::Contabilidad::AccountingFile.new(contents: remuneraciones, extension: 'xlsx', name_formatter: -> (name) { "#{name}-Remuneraciones" }),
      bonos: Exportador::Contabilidad::AccountingFile.new(contents: bonos, extension: 'xlsx', name_formatter: -> (name) { "#{name}-BBSS" }),
      liquidaciones: Exportador::Contabilidad::AccountingFile.new(contents: liquidaciones, extension: 'xlsx', name_formatter: -> (name) { "#{name}-Liquidaciones" }),
    }
  end

  def excel_data variable, obj_contabilidad
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, "Centralizacion"
    Exportador::BaseXlsx.escribir_celdas sheet, [TITULOS], offset: 0
    mes_anio = variable.end_date.strftime('%m%Y')

    agrupacion = obj_contabilidad.sort_by(&:deber_o_haber).reverse.group_by do |l|
      {
        deber_o_haber: l.deber_o_haber,
        cuenta_contable: search_account(l),
        nombre_cuenta: search_name_account(l).presence || l.glosa,
        nombre_trabajador: get_nombre_trabajador(l),
        codigo_centro_costo: get_centro_costo(l, 0).presence,
        nombre_centro_costo: get_centro_costo(l, 1).presence,
      }
    end

    excel_data = agrupacion.map do |k, v|
      [
        nil,
        nil,
        nil,
        nil,
        mes_anio,
        k[:deber_o_haber] == "D" ? v.sum(&:monto) : "-#{v.sum(&:monto)}".to_f.round(2),
        'base.PEN',
        k[:deber_o_haber] == "D" ? v.sum(&:monto) : nil,
        k[:deber_o_haber] == "C" ? v.sum(&:monto) : nil,
        k[:cuenta_contable],
        k[:nombre_cuenta],
        k[:nombre_trabajador],
        k[:codigo_centro_costo],
        k[:nombre_centro_costo],
      ]
    end
    Exportador::BaseXlsx.escribir_celdas sheet, excel_data, offset: 1
    Exportador::BaseXlsx.autofit sheet, [TITULOS]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def generate_data(_empresa, variable, obj_contabilidad, **_args)
    return [] if obj_contabilidad.nil? || obj_contabilidad.empty?
    data = []
    mes_anio = variable.end_date.strftime('%m%Y')

    agrupacion = obj_contabilidad.sort_by(&:deber_o_haber).reverse.group_by do |l|
      {
        deber_o_haber: l.deber_o_haber,
        cuenta_contable: search_account(l),
        nombre_cuenta: search_name_account(l) || l.glosa,
        nombre_trabajador: get_nombre_trabajador(l),
        codigo_centro_costo: get_centro_costo(l, 0).presence,
        nombre_centro_costo: get_centro_costo(l, 1).presence,
      }
    end

    agrupacion.each do |k, v|
      data << {
        id: nil,
        line_ids_account_id_id: nil,
        line_ids_partner_id_id: nil,
        apuntes_contables_cuenta_analitica_id_externo: nil,
        line_ids_name: mes_anio,
        line_ids_amount_currency: k[:deber_o_haber] == "D" ? v.sum(&:monto) : "-#{v.sum(&:monto)}",
        line_ids_currency_id_id: 'base.PEN',
        line_ids_debit: k[:deber_o_haber] == "D" ? v.sum(&:monto) : nil,
        line_ids_credit: k[:deber_o_haber] == "C" ? v.sum(&:monto) : nil,
        cod_cta_contable: k[:cuenta_contable],
        cuenta_contable: k[:nombre_cuenta],
        apellidos_nombres: k[:nombre_trabajador],
        codigo_costo: k[:codigo_centro_costo],
        nombre_costo: k[:nombre_centro_costo],
      }
    end
    data
  end

  private
    def search_account l
      l.nombre_cuenta == "afp" ? afp_method_account(l) : l.cuenta_contable
    end

    def afp_method_account l
      case l.afp&.upcase
      when "AFP HABITAT"
        afp_habitat
      when "AFP INTEGRA"
        afp_integra
      when "PRIMA AFP"
        prima_afp
      when "PROFUTURO AFP"
        profuturo_afp
      end&.numero
    end

    def afp_habitat
      @afp_habitat ||= CuentaContable.cuentas_contables[:item]["afp habitat"]
    end

    def afp_integra
      @afp_integra ||= CuentaContable.cuentas_contables[:item]["afp integra"]
    end

    def prima_afp
      @prima_afp ||= CuentaContable.cuentas_contables[:item]["prima afp"]
    end

    def profuturo_afp
      @profuturo_afp ||= CuentaContable.cuentas_contables[:item]["profuturo afp"]
    end

    def get_nombre_trabajador l
      "#{l.last_name} #{l.second_last_name}, #{l.first_name}" if l.cuenta_custom_attrs&.dig('Agrupacion') == 'Trabajador'
    end

    def get_centro_costo l, number
      l.centro_costo.to_s.split('-')[number] if l.cuenta_custom_attrs&.dig('Agrupacion') == 'Cencos'
    end

    def search_name_account l
      l.nombre_cuenta == "afp" ? afp_method_name_account(l) : l.cuenta_custom_attrs&.dig("Nombre de la cuenta")
    end

    def afp_method_name_account l
      case l.afp&.upcase
      when "AFP HABITAT"
        afp_habitat
      when "AFP INTEGRA"
        afp_integra
      when "PRIMA AFP"
        prima_afp
      when "PROFUTURO AFP"
        profuturo_afp
      end&.nombre&.upcase
    end

end

# EXAMPLE 54
#piura_ga.rb


# frozen_string_literal: true

# Archivo de Centralizacion Personalizada cliente Piura Gas
class Exportador::Contabilidad::Peru::Personalizadas::PiuraGa < Exportador::Contabilidad::Peru::CentralizacionContable
  def initialize
    super()
    @extension = 'xlsx'
  end

  HEADER_1 = [
    "Cuenta de mayor/Código SN",
    "Cuenta de mayor/Nombre SN",
    "Cuenta asociada",
    "Débito",
    "Crédito",
    "Establecimiento",
    "Centro de Costos",
    "Unidad de Negocio",
    "Destino",
  ].freeze

  CUENTAS_A_OMITIR = [
    'buk_sctr_deber',
    'buk_sctr_haber',
  ].freeze

  def generate_doc(_empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    mes_y_anio = I18n.l(date, format: '%B %y').upcase

    obj_contabilidad.reject!{|l| CUENTAS_A_OMITIR.include?(l.nombre_cuenta)}

    obj_contabilidad_grupo = obj_contabilidad.group_by{|l| l.cuenta_custom_attrs["Tipo de asiento"] || ""}

    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []

    obj_contabilidad_grupo.each do |k, v|
      generate_centralizacion(book, k.presence || "Sin Categoria", v, mes_y_anio)
    end
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def generate_centralizacion(book, sheet_name, obj_contabilidad, mes_y_anio)
    sheet = Exportador::BaseXlsx.crear_hoja book, sheet_name
    cabecera = ["#{sheet_name} #{mes_y_anio}"]
    Exportador::BaseXlsx.crear_encabezado(sheet, cabecera, 0)
    Exportador::BaseXlsx.crear_encabezado(sheet, HEADER_1, 2)


    agrupador = obj_contabilidad.group_by do |l|
      establecimiento, centro_costo, unidad_negocio, destino = get_attrs_job(l)
      {
        c_mayor: get_cuenta_contable(l),
        nom_mayor: get_glosa(l),
        cuenta_asociada: search_account(l),
        deber_o_haber: l.deber_o_haber,
        establecimiento: establecimiento,
        cenco: centro_costo,
        u_negocio: unidad_negocio,
        destino: destino,
      }
    end
    data = agrupador.map do |k, v|
      [
        k[:c_mayor],
        k[:nom_mayor],
        k[:cuenta_asociada],
        k[:deber_o_haber] == "D" ? v.sum(&:monto) : nil,
        k[:deber_o_haber] == "C" ? v.sum(&:monto) : nil,
        k[:establecimiento],
        k[:cenco],
        k[:u_negocio],
        k[:destino],
      ]
    end
    Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 3, number_format: "###0.00"
    Exportador::BaseXlsx.autofit sheet, [HEADER_1]
  end

  private

    def get_cuenta_contable obj
      return obj.cuenta_custom_attrs["RUC"] if obj.cuenta_custom_attrs["RUC"].present?
      return "E000#{obj.numero_documento}" if obj.cuenta_custom_attrs["Código de Socio de Negocio (Cuenta Asociada)"].present?
      search_account(obj)
    end

    def get_glosa obj
      return obj.cuenta_custom_attrs['Razon Social'] if obj.cuenta_custom_attrs["RUC"].present?
      obj.cuenta_custom_attrs["Código de Socio de Negocio (Cuenta Asociada)"].present? ? obj.employee.nombre_completo_invertido_con_coma.upcase : search_glosa_afp(obj)
    end

    def get_attrs_job obj
      [obj.job_custom_attrs["Establecimiento"], obj.centro_costo, obj.job_custom_attrs["Unidad de Negocios"], obj.job_custom_attrs["Destino"]] if obj.cuenta_custom_attrs["Agrupador"].to_s.casecmp("cenco").zero?
    end
end

# EXAMPLE 55
#palante.rb


# frozen_string_literal: true

# Clase para generar contabilidad personalizad de Palante
class Exportador::Contabilidad::Peru::Personalizadas::Palante < Exportador::Contabilidad
  include ContabilidadPeruHelper

  def initialize
    super()
    @extension = 'xlsx'
  end
  CABECERA_DATA = [
    'Código Interno',
    'Periodo',
    'linea',
    'Cuenta',
    'Monto',
    'Tipo',
    'Glosa',
    'cc1',
    'cc2',
    'cc3',
    'cc4',
    'cc5',
    'ref1',
    'ref2',
  ].freeze

  CABECERA = [
    'Código Interno',
    'Periodo',
    'Sistema o RUC',
    'Código_SAP',
    'Fecha_Mig.',
    'Fecha_Contabilización',
    'Fecha_vencimiento',
    'Código_Transacción',
    'Glosa',
    'Fecha_Reversión',
    'Fecha_Error',
    'Mensaje_Envío',
    'Fecha_modif',
    'Estado',
  ].freeze

  NO_CONTABILIZAR_INFORMATIVOS = [
    "buk_provision_vacaciones",
    "buk_provision_gratificacion",
    "buk_provision_cts",
    "buk_provision_bonificacion_gratificacion",
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    obj_conta = descartar_informativos(obj_contabilidad)
    obj_contabilidad_ordenado = obj_conta.group_by{|l| l.cuenta_custom_attrs&.dig("Tipo de Asiento") || "Sin asiento"}

    hashes = {}
    obj_contabilidad_ordenado.each do |k, obj|
      concepto = k
      cabecera = generate_excel_cabecera(obj, variable, empresa)
      hashes["Cabecera_#{k}".to_sym] = Exportador::Contabilidad::AccountingFile.new(contents: cabecera, name_formatter: -> (name) {"#{name} CABECERA #{concepto}"})

      libro = generate_excel_data(obj, variable, empresa)
      hashes["Libro_#{k}".to_sym] = Exportador::Contabilidad::AccountingFile.new(contents: libro, name_formatter: -> (name) {"#{name} Asiento #{concepto}"})
    end
    hashes
  end

  def generate_data(empresa, variable, obj_contabilidad, **_args)
    return [] unless obj_contabilidad.present?
    var_date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    mes = var_date.strftime("%m")
    mes_str = I18n.l(var_date, format: '%B').upcase
    fecha = var_date.strftime("%Y%m%d")
    anio = var_date.strftime("%Y")

    obj_conta = descartar_informativos(obj_contabilidad)
    planilla = obj_conta.select{|l| l.cuenta_custom_attrs&.dig("Tipo de Asiento") == 'Planilla Mensual'}
    vacaciones = obj_conta.select{|l| l.cuenta_custom_attrs&.dig("Tipo de Asiento") == 'Provisión Vacaciones'}
    gratificacion = obj_conta.select{|l| l.cuenta_custom_attrs&.dig("Tipo de Asiento") == 'Provisión Gratificación'}
    cts = obj_conta.select{|l| l.cuenta_custom_attrs&.dig("Tipo de Asiento") == 'Provisión CTS'}
    liquidacion = obj_conta.select{|l| l.cuenta_custom_attrs&.dig("Tipo de Asiento") == 'Liquidaciones'}
    cabecera_planilla = generate_doc_cabecera(empresa, planilla, mes, fecha, anio, mes_str)
    cabecera_vaciones = generate_doc_cabecera(empresa, vacaciones, mes, fecha, anio, mes_str)
    cabecera_gratificacion = generate_doc_cabecera(empresa, gratificacion, mes, fecha, anio, mes_str)
    cabecera_cts = generate_doc_cabecera(empresa, cts, mes, fecha, anio, mes_str)
    cabecera_liquidacion = generate_doc_cabecera(empresa, liquidacion, mes, fecha, anio, mes_str)
    cabecera_planilla + cabecera_vaciones + cabecera_gratificacion + cabecera_cts + cabecera_liquidacion
  end

  private
    def generate_excel_cabecera obj, variable, empresa
      return unless obj.present?
      book = Exportador::BaseXlsx.crear_libro
      book.worksheets = []
      sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
      Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA, 0)

      var_date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
      mes = var_date.strftime("%m")
      mes_str = I18n.l(var_date, format: '%B').upcase
      fecha = var_date.strftime("%Y%m%d")
      anio = var_date.strftime("%Y")

      agrupador = agrupacion_cabecera(obj, empresa, fecha, anio, mes_str)

      excel_data = agrupador.map do |k, _v|
        [
          k[:code],
          "#{anio}-#{mes}",
          k[:rut_empresa],
          nil,
          nil,
          fecha,
          fecha,
          k[:codigo_transaccion],
          k[:codigo_transaccion_glosa],
        ]
      end

      Exportador::BaseXlsx.escribir_celdas sheet, excel_data, offset: 1, number_format: "###0.00"
      Exportador::BaseXlsx.autofit sheet, [CABECERA]
      Exportador::BaseXlsx.cerrar_libro(book).contenido
    end

    def generate_doc_cabecera(empresa, obj_contabilidad, mes, fecha, anio, mes_str)
      agrupado = agrupacion_cabecera(obj_contabilidad, empresa, fecha, anio, mes_str)

      agrupado.map do |k, _v|
        [
          codigo_interno: k[:code],
          periodo: "#{anio}-#{mes}",
          sistema_o_ruc: k[:rut_empresa],
          codigo_sap: "null",
          fecha_mig: "null",
          fecha_contabilizacion: fecha,
          fecha_vencimiento: fecha,
          codigo_transaccion: k[:codigo_transaccion],
          glosa: k[:codigo_transaccion_glosa],
          fecha_revision: "null",
          fecha_error: "null",
          mensaje_envio: "null",
          fecha_modif: "null",
          estado: "null",
          data: data_api(empresa, obj_contabilidad, mes, fecha, anio),
        ]
      end
    end

    def agrupacion_cabecera obj, empresa, fecha, anio, mes_str
      obj.group_by do |o|
        {
          code: search_code(o, fecha, empresa),
          rut_empresa: empresa.rut&.humanize,
          codigo_transaccion: search_code_asiento(o),
          codigo_transaccion_glosa: search_code_glosa(o, mes_str, anio),
        }
      end
    end

    def generate_excel_data obj, variable, empresa
      return unless obj.present?
      book = Exportador::BaseXlsx.crear_libro
      book.worksheets = []
      sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
      Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA_DATA, 0)

      var_date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
      mes = var_date.strftime("%m")
      fecha = var_date.strftime("%Y%m%d")
      anio = var_date.strftime("%Y")

      agrupador = agrupacion_cuerpo(obj, empresa, fecha)

      excel_data = agrupador.map.with_index(1) do |(k, v), index|
        [
          k[:code],
          "#{anio}-#{mes}",
          index,
          k[:cuenta_contable],
          v.sum(&:monto),
          k[:deber_haber] == "D" ? "D" : "H",
          k[:glosa],
          k[:centro_costo],
        ]
      end

      Exportador::BaseXlsx.escribir_celdas sheet, excel_data, offset: 1, number_format: "###0.00"
      Exportador::BaseXlsx.autofit sheet, [CABECERA_DATA]
      Exportador::BaseXlsx.cerrar_libro(book).contenido
    end


    def data_api(empresa, obj_contabilidad, mes, fecha, anio)
      return [] unless obj_contabilidad.present?
      correlativo = 0
      data = []

      agrupado = agrupacion_cuerpo(obj_contabilidad, empresa, fecha)

      agrupado.each do |k, v|
        data << {
          codigo_interno: k[:code],
          periodo: "#{anio}-#{mes}",
          linea: (correlativo += 1).to_s,
          cuenta: k[:cuenta_contable],
          monto: v.sum(&:monto),
          tipo: k[:deber_haber] == "D" ? "D" : "H",
          glosa: k[:glosa],
          cc1: k[:centro_costo],
          cc2: "null",
          cc3: "null",
          cc4: "null",
          cc5: "null",
          ref1: "null",
          ref2: "null",
        }
      end
      data
    end.presence || []

    def agrupacion_cuerpo obj, empresa, fecha
      obj.group_by do |o|
        {
          code: search_code(o, fecha, empresa),
          cuenta_contable: o.cuenta_contable,
          glosa: o.nombre_cuenta,
          centro_costo: search_cc(o),
          deber_haber: o.deber_o_haber,
        }
      end
    end

    def get_nombre_cenco l
      l.centro_costo_custom_attrs&.dig("Nombre del Centro de Costo") unless l.cuenta_custom_attrs&.dig("Agrupador") == "TOTAL"
    end

    def descartar_informativos(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_INFORMATIVOS.include?(l.item_code)
      end
    end

    def search_code obj, fecha, empresa
      cod_attr = obj.cuenta_custom_attrs&.dig("Código del Tipo de Asiento")
      rut_empresa = empresa.rut&.humanize
      case cod_attr
      when "NPRC"
        "#{fecha}1#{rut_empresa}"
      when "NPRV"
        "#{fecha}2#{rut_empresa}"
      when "NPRG"
        "#{fecha}3#{rut_empresa}"
      when "NPLA"
        "#{fecha}4#{rut_empresa}"
      when "NLIQ"
        "#{fecha}5#{rut_empresa}"
      end
    end

    def search_code_asiento obj
      tipo_asiento = obj.cuenta_custom_attrs&.dig("Tipo de Asiento")
      case tipo_asiento
      when "Planilla Mensual"
        "NPLA"
      when "Liquidaciones"
        "NLIQ"
      when "Provisión CTS"
        "NPRC"
      when "Provisión Gratificación"
        "NPRG"
      when "Provisión Vacaciones"
        "NPRV"
      end
    end

    def search_code_glosa obj, mes_str, anio
      tipo_asiento = obj.cuenta_custom_attrs&.dig("Tipo de Asiento")
      case tipo_asiento
      when "Planilla Mensual"
        "PLANILLA EMPLEADOS #{mes_str} #{anio}"
      when "Liquidaciones"
        "LIQUIDACIONES #{mes_str} #{anio}"
      when "Provisión CTS"
        "PROVISIÓN CTS #{mes_str} #{anio}"
      when "Provisión Gratificación"
        "PROVISIÓN GRATIFICACION #{mes_str} #{anio}"
      when "Provisión Vacaciones"
        "PROVISIÓN VACACIONES #{mes_str} #{anio}"
      end
    end
end

# EXAMPLE 56
#alignet.rb


# frozen_string_literal: true

# Clase de centralizacion personalizada de Alignet
class Exportador::Contabilidad::Peru::Personalizadas::Alignet < Exportador::Contabilidad
  def initialize
    super()
    @extension = 'xlsx'
  end

  def create_lineas_liquidacion(liquidacions, **args)
    ::Contabilidad::Peru::LineasLiquidacionesService.new(liquidacions, **args)
  end

  CABECERA = [
    "csub_diar",
    "cfile_nro",
    "ncompr_nro",
    "cid_item",
    "dfch_conta",
    "ccod_ctalo",
    "ccod_cutil",
    "ccod_ccosto",
    "ccod_coa",
    "cregto",
    "ccod_mon",
    "ndebe_mof",
    "nhaber_mof",
    "ndebe_mex",
    "nhaber_mex",
    "nt_cambio",
    "cglosa",
    "ccod_proy",
  ].freeze

  TITULOS_CABECERA = [
    'csub_diar',
    'cfile_nro',
    'ncompr_nro',
    'dfch_conta',
    'ccod_coa',
    'nt_cambio',
    'ndebe_mof',
    'nhaber_mof',
    'ndebe_mex',
    'nhaber_mex',
    'cglosa',
    'tobs',
    'ccod_proy',
    'cindentificador',
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet2 = Exportador::BaseXlsx.crear_hoja book, 'Cabecera'
    Exportador::BaseXlsx.crear_encabezado(sheet2, TITULOS_CABECERA, 0)
    data_cabecera = generate_cabecera(obj_contabilidad, variable.id, empresa.id)
    Exportador::BaseXlsx.escribir_celdas sheet2, [data_cabecera], number_format: "#,##0", offset: 1
    Exportador::BaseXlsx.autofit sheet2, [TITULOS_CABECERA]

    glosas_principales = obj_contabilidad.select{|l| l.cuenta_custom_attrs&.dig("Glosa Principal")}.map do |obj|
      obj.cuenta_custom_attrs&.dig("Glosa Principal")
    end.uniq

    glosas_principales.each do |glosa|
      sheet = Exportador::BaseXlsx.crear_hoja book, glosa
      object = obj_contabilidad.select{|obj| obj.cuenta_custom_attrs&.dig("Glosa Principal") == glosa}
      Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA, 0)
      data = generate_body(object, variable, empresa)
      Exportador::BaseXlsx.escribir_celdas sheet, data, number_format: "#,##0", offset: 1
      Exportador::BaseXlsx.autofit sheet, [CABECERA]
    end
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  private
    def generate_body object, variable, empresa
      return unless object
      fecha = Time.zone.now.strftime("%d/%m/%Y")
      index = 0
      kpi = kpi_cambio(variable.id, empresa.id).to_f || 1
      group = object.sort_by{|l| [l.cuenta_custom_attrs&.dig("Agrupación") || '']}.group_by do |obj|
        {
          glosa_principal: obj.cuenta_custom_attrs&.dig("Glosa Principal"),
          num_comprobante: obj.cuenta_custom_attrs&.dig("Numero de Comprobante"),
          numero_cuenta: search_account(obj),
          agrupacion: obj.cuenta_custom_attrs&.dig("Agrupación"),
          aux: aux(obj),
          cc: centro_costo(obj),
          glosa_detalle: obj.cuenta_custom_attrs&.dig("Glosa detalle"),
          deber_o_haber: obj.deber_o_haber,
        }
      end
      group.map do |k, v|
        index += 1
        [
          k[:glosa_principal],
          k[:glosa_principal],
          k[:num_comprobante],
          index,
          fecha,
          k[:numero_cuenta],
          nil,
          k[:cc],
          k[:aux],
          nil,
          "01",
          k[:deber_o_haber] == 'D' ? v.sum(&:monto) : nil,
          k[:deber_o_haber] == 'C' ? v.sum(&:monto) : nil,
          k[:deber_o_haber] == 'D' && kpi > 0 ? (v.sum(&:monto) / kpi) : nil,
          k[:deber_o_haber] == 'C' && kpi > 0 ? (v.sum(&:monto) / kpi) : nil,
          kpi.to_s,
          k[:glosa_detalle],
          nil,
        ]
      end
    end

    def search_account object
      afp = [
        'afp',
        'buk_finiquito_aporte_afp',
        'buk_finiquito_comision_afp',
        'buk_finiquito_seguro_afp',
      ].freeze
      if afp.include?(object.nombre_cuenta)
        object.cuenta_custom_attrs&.dig(object.afp)
      else
        object.cuenta_contable
      end
    end

    def aux object
      case object.cuenta_custom_attrs&.dig("Agrupación")
      when 'DNI'
        object.numero_documento
      when 'RUC'
        object.ruc_afp
      end.to_s
    end

    def kpi_cambio variable_id, empresa_id
      @kpi_dolar ||= Hash.new do |h, empresa_id_arg|
        conditions = {
          variable_id: variable_id,
          empresa_id: empresa_id_arg,
          kpis: { code: "tipo_de_cambio"},
        }
        h[empresa_id_arg] = KPIDatum.joins(:kpi).where(conditions).single_or_nil!&.decimal_value
      end
      @kpi_dolar[empresa_id]
    end

    def generate_cabecera obj_contabilidad, variable_id, empresa_id
      fecha = DateTime.now.strftime("%d/%m/%Y")
      total_debe = obj_contabilidad.select{|l| l.cuenta_custom_attrs&.dig("Glosa Principal") && l.deber?}.sum(&:monto)
      total_haber = obj_contabilidad.select{|l| l.cuenta_custom_attrs&.dig("Glosa Principal") && l.haber?}.sum(&:monto)
      kpi = kpi_cambio(variable_id, empresa_id)
      [
        'REM',
        'REM',
        1,
        fecha,
        '20333372216',
        kpi,
        total_debe,
        total_haber,
        kpi.present? && kpi > 0 ? (total_debe / kpi) : nil,
        kpi.present? && kpi > 0 ? (total_haber / kpi) : nil,
        "ASIENTO DE REMUNERACIONES",
      ]
    end

    def centro_costo obj
      obj.centro_costo if obj.cuenta_custom_attrs&.dig("Agrupación") == 'CC'
    end
end

# EXAMPLE 57
#cuponatic.rb


# frozen_string_literal: true

#
#Clase para la centralizacion personaliza cliente Cuponatic Peru
class Exportador::Contabilidad::Peru::Personalizadas::Cuponatic < Exportador::Contabilidad
  include ContabilidadPeruHelper
  def initialize
    super()
    @extension = 'xlsx'
  end
  TITULOS_1 = [
    'Cuenta',
    'Observacion',
    'CC',
    'Proyecto',
    'Mov.Bancario',
    'Documento',
    'Tipo',
    'Rut',
    'Fecha',
    'DEBE',
    'HABER',
  ].freeze
  TITULOS_2 = [
    'Cuenta',
    'Descripcion',
    'Centro de Costo',
    'Rut',
    'Descripcion',
    'Documento',
    'Fecha Venc.',
    'Debe',
    'Haber',
    'Observacion',
  ].freeze
  NO_CONTABILIZAR_INFORMATIVOS = [
    "buk_provision_gratificacion",
    "buk_provision_vacaciones",
    "buk_provision_cts",
    "buk_provision_bonificacion_gratificacion",
  ].freeze
  def generate_doc(_empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?
    obj_contabilidad = descartar_informativos(obj_contabilidad)
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    var_date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    anio_mes = var_date.strftime('%Y%m')
    fecha = var_date.strftime('%d-%m-%Y')
    mes = I18n.l(Variable::Utils.end_of_period(variable.start_date, variable.period_type), format: '%B').capitalize
    sheet_formato = Exportador::BaseXlsx.crear_hoja book, "Formato carga voucher runa"
    sheet_planilla = Exportador::BaseXlsx.crear_hoja book, "Voucher Planilla #{mes}. PE"
    Exportador::BaseXlsx.crear_encabezado(sheet_formato, TITULOS_1, 0)
    Exportador::BaseXlsx.crear_encabezado(sheet_planilla, TITULOS_2, 0)

    agrupador_formato = obj_contabilidad.group_by do |p|
      agrupador_formato(p)
    end
    excel_data_formato = agrupador_formato.map do |k, v|
      print_data_formato(k, v, fecha, anio_mes)
    end
    Exportador::BaseXlsx.escribir_celdas sheet_formato, excel_data_formato, offset: 1, number_format: '###0.00'
    excel_data_planilla = obj_contabilidad.map do |l|
      print_data_planilla(l, fecha, anio_mes)
    end
    Exportador::BaseXlsx.escribir_celdas sheet_planilla, excel_data_planilla, offset: 1, number_format: '###0.00'

    Exportador::BaseXlsx.autofit sheet_formato, [TITULOS_1]
    Exportador::BaseXlsx.autofit sheet_planilla, [TITULOS_2]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end
  private
    def search_observacion obj
      observacion = obj.cuenta_custom_attrs&.dig("Observacion")
      observacion_2 = obj.cuenta_custom_attrs&.dig("Observacion 2")
      observacion_3 = obj.cuenta_custom_attrs&.dig("Observacion 3")
      case observacion
      when "item"
        obj.glosa
      when "nombre completo"
        "#{obj.glosa} #{obj.first_name} #{obj.last_name} #{obj.second_last_name}"
      when "Adelanto Remuneracion"
        if obj.item_code == "adelanto_de_vacaciones"
          observacion_2
        elsif obj.item_code == "descuento_eps"
          observacion_3
        else
          observacion
        end
      else
        observacion
      end
    end
    def search_cc obj
      mostrar_cc = obj.cuenta_custom_attrs&.dig("Centro de Costo")
      cc_default = obj.cuenta_custom_attrs&.dig("Ceco Default")
      cc_default || obj.centro_costo if mostrar_cc&.parameterize == "si"
    end
    def agrupador_formato p
      {
        cuenta_contable: p.cuenta_contable,
        observacion: search_observacion(p),
        centro_costo: search_cc(p),
        rut: p.numero_documento&.humanize,
        deber_o_haber: p.deber_o_haber,
      }
    end
    def print_data_formato k, v, fecha, anio_mes
      [
        k[:cuenta_contable],
        k[:observacion],
        k[:centro_costo],
        nil,
        nil,
        anio_mes,
        nil,
        k[:rut],
        fecha,
        k[:deber_o_haber] == "D" ? v.sum(&:monto) : nil, #K
        k[:deber_o_haber] == "C" ? v.sum(&:monto) : nil, #L
      ]
    end
    def print_data_planilla obj, fecha, anio_mes
      [
        obj.cuenta_contable,
        obj.cuenta_custom_attrs&.dig("Nombre Cuenta"),
        search_cc(obj),
        obj.numero_documento&.humanize,
        "#{obj.first_name} #{obj.last_name} #{obj.second_last_name}",
        anio_mes,
        fecha,
        obj.deber.presence || 0,
        obj.haber.presence || 0,
        search_observacion(obj),
      ]
    end
    def descartar_informativos(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_INFORMATIVOS.include?(l.item_code)
      end
    end
end

# EXAMPLE 58
#contabilidad_multivet.rb


# frozen_string_literal: true

#
# clase para generar centralizacion para cliente ContabilidadMultivet
class Exportador::Contabilidad::Peru::Personalizadas::ContabilidadMultivet < Exportador::Contabilidad
  include ContabilidadPeruHelper

  NO_CONTABILIZAR_INFORMATIVOS = ["buk_vida_ley"].freeze

  def generate_data(_empresa, variable, obj_contabilidad, **_args)
    return [] if obj_contabilidad.nil? || obj_contabilidad.empty?

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    date_ddmmyyyy = I18n.l(date, format: '%d/%m/%Y')
    date_month_year = I18n.l(date, format: '%B %Y').upcase

    obj_contabilidad = descartar_informativos(obj_contabilidad)

    grouped = obj_contabilidad.group_by{|l| l.cuenta_custom_attrs["Tipo de Asiento"].presence || "Sin clasificar"}

    grouped.map do |k, obj|
      tipo_asiento = k
      generate_api_cuerpo(obj, tipo_asiento, date_ddmmyyyy, date_month_year)
    end
  end

  private

    def search_account_afp_by_cencos obj
      cenco = obj.centro_costo
      return obj.cuenta_custom_attrs[cenco] unless obj.cuenta_custom_attrs["AFP"].to_s.casecmp('si').zero?
      afp_method(obj).custom_attrs[cenco]
    end

    def descartar_informativos(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_INFORMATIVOS.include?(l.item_code)
      end
    end

    def generate_api_cuerpo(obj_contabilidad, tipo_asiento, date_ddmmyyyy, date_month_year)
      agrupador = obj_contabilidad.group_by do |l|
        {
          cuenta_contable: search_account_afp_by_cencos(l),
          deber_o_haber: l.deber_o_haber,
          tipo_documento: l.cuenta_custom_attrs["Tipos Asientos"],
          num_documento: l.cuenta_custom_attrs["Número Documento"],
          agrupador_dni: search_numero_documento(l),
          agrupador_cenco: search_cc(l),
        }
      end

      agrupador.map.with_index(1) do |(k, v), index|
        {
          Line: index,
          SectionJour: k[:tipo_documento],
          PostingDate: date_ddmmyyyy,
          DocumentNum: k[:num_documento],
          AccountType: nil,
          AccountNum: k[:cuenta_contable],
          Description: "#{tipo_asiento} #{date_month_year}",
          PostingGroup: nil,
          CurrencyCode: nil,
          AmountCur: k[:deber_o_haber] == "D" ? format("%#.2f", v.sum(&:monto)) : format("%#.2f", (v.sum(&:monto) * -1)),
          AmountMST: k[:deber_o_haber] == "D" ? format("%#.2f", v.sum(&:monto)) : format("%#.2f", (v.sum(&:monto) * -1)),
          DocumentType: "00",
          Comment: nil,
          DimCode1: nil,
          DimCode2: nil,
          DimCode3: nil,
          DimCode4: nil,
          DimCode5: nil,
          DimCode6: nil,
          DimCode7: nil,
          DimCode8: nil,
        }
      end
    end
end

# EXAMPLE 59
#floid_peru.rb


# frozen_string_literal: true

# Clase para generar centralizacion de cliente Floid Peru
class Exportador::Contabilidad::Peru::Personalizadas::FloidPeru < Exportador::Contabilidad::Peru::CentralizacionContable
  require 'csv'
  def initialize
    super()
    @extension = 'txt'
  end

  NO_CONTABILIZAR_INFORMATIVOS = [
    'provision_bonificacion_extraordinaria_gratificacion_deber',
    'provision_bonificacion_extraordinaria_gratificacion_haber',
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    obj_contabilidad = descartar_cuentas(obj_contabilidad)
    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    full_date = I18n.l(date, format: "%d/%m/%Y")
    date_mm = I18n.l(date, format: "%m")
    date_yyyy = I18n.l(date, format: "%Y")
    date_yyyymm = I18n.l(date, format: "%Y%m")
    date_mmstr = I18n.l(date, format: '%B %Y').capitalize
    name_file = "#{empresa.rut}rd#{date_yyyymm}"
    dolar = kpi_dolar(variable.id, empresa.id, 'tipo_de_cambio') || 1

    obj_contabilidad = obj_contabilidad.group_by{|l| l.cuenta_custom_attrs['Tipo de asiento']}

    obj_contabilidad.map do |k, v|
      txt_file = generate_txt(v, k, date_yyyy, date_mm, full_date, date_mmstr, date_yyyymm, dolar)
      ["file_#{k}", Exportador::Contabilidad::AccountingFile.new(contents: txt_file, name_formatter: -> (_name) {k.present? ? "#{name_file}_#{k}" : "#{name_file}_Sin tipo de Asiento"})]
    end.to_h
  end
  private

    def generate_txt(obj_contabilidad, tipo_asiento, date_yyyy, date_mm, full_date, date_mmstr, date_yyyymm, dolar)
      glosa_general = "#{tipo_asiento} #{date_mmstr}"

      obj_conta_agrupado = obj_contabilidad.group_by do |l|
        codaux, serdoc, nrodoc, num_documento = cod_auxiliar(l, date_yyyymm)
        {
          nro_cpb: l.cuenta_custom_attrs["NROCPB"].presence,
          cod_tdc: get_codtdc(l),
          cuenta_contable: search_account(l),
          centro_costo: search_cenco(l),
          cod_aux: codaux,
          ser_doc: serdoc,
          nro_doc: nrodoc,
          rut: num_documento,
          glosa: get_glosa(l),
          tp_dolle: l.cuenta_custom_attrs["Dato TPODLLE"].presence,
          deber_o_haber: l.deber_o_haber,
        }
      end

      CSV.generate(col_sep: "|", encoding: 'windows-1252', row_sep: "\r\n") do |csv|
        obj_conta_agrupado.each.with_index(1) do |(k, v), index|
          csv << [
            date_yyyy,
            "0401",
            k[:nro_cpb],
            date_mm,
            full_date,
            glosa_general,
            nil,
            "D",
            index.to_s.rjust(4, '0'),
            index.to_s.rjust(4, '0'),
            k[:cod_tdc],
            k[:cuenta_contable],
            k[:centro_costo],
            k[:cod_aux],
            k[:ser_doc],
            k[:nro_doc],
            full_date,
            full_date,
            full_date,
            k[:rut],
            k[:glosa],
            nil,
            k[:deber_o_haber] == 'C' ? 'H' : 'D',
            k[:tp_dolle],
            "N",
            "V",
            dolar,
            format("%#.2f", v.sum(&:monto).to_f.round(2)),
            format("%#.2f", (v.sum(&:monto).to_f.round(2) / dolar)),
            nil,
            index.to_s.rjust(4, '0'),
          ]
        end
      end
    end

    def get_codtdc obj
      "00" if  obj.cuenta_custom_attrs["Mostrar CODTDC"].to_s.casecmp("si").zero?
    end

    def descartar_cuentas(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_INFORMATIVOS.include?(l.nombre_cuenta)
      end
    end

    def cod_auxiliar obj, date_yyyymm
      [obj.job_custom_attrs["CODAUX"], "PLLA", "0000#{date_yyyymm}", obj.numero_documento.to_s] if obj.cuenta_custom_attrs["Mostrar CODAUX"].to_s.casecmp('si').zero?
    end

    def get_glosa obj
      search_glosa_afp(obj) if obj.cuenta_custom_attrs["Agrupador"] != "TOTAL"
    end
end

# EXAMPLE 60
#gladcon.rb


# frozen_string_literal: true

#
# Estructura contable para generar centralizacion personalizada Gladcon
class Exportador::Contabilidad::Peru::Personalizadas::Gladcon < Exportador::Contabilidad::Peru::CentralizacionContable
  def initialize
    super
    @extension = "xlsx"
  end

  ENCABEZADO_1 = [
    "CSUBDIA",
    "CCOMPRO",
    "CFECCOM",
    "CCODMON",
    "CSITUA",
    "CTIPCAM",
    "CGLOSA",
    "CTOTAL",
    "CTIPO",
    "CFLAG",
    "CFECCAM",
    "CORIG",
    "CFORM",
    "CTIPCOM",
    "CEXTOR",
  ].freeze

  ENCABEZADO_2 = [
    "DSUBDIA",
    "DCOMPRO",
    "DSECUE",
    "DFECCOM",
    "DCUENTA",
    "DCODANE",
    "DCENCOS",
    "DCODMON",
    "DDH",
    "DIMPORT",
    "DTIPDOC",
    "DNUMDOC",
    "DFECDOC",
    "DFECVEN",
    "DAREA",
    "DFLAG",
    "DXGLOSA",
    "DCODANE2",
    "DUSIMPOR",
    "DMNIMPOR",
    "DCODARC",
    "DNDOREF",
    "DFECREF",
    "DBIMREF",
    "DIGVREG",
  ].freeze

  ENCABEZADO_3 = [
    "AVANEXO",
    "ACODANE",
    "ADESANE",
    "AREFANE",
    "ARUC",
    "ACODMON",
    "AESTADO",
    "ATIPTRA",
    "APATERNO",
    "AMATERNO",
    "ANOMBRE",
    "AFORMSUS",
    "ATELEFO",
    "APROVIN",
    "ADEPART",
    "APAIS",
    "AEMAIL",
    "AHOST",
    "ADOCOIDE",
    "ANUMIDE",
  ].freeze

  NO_CONTABILIZAR_INFORMATIVOS = [
    "buk_provision_vacaciones",
    "buk_vida_ley",
    "buk_sctr_pension",
    "buk_sctr_salud",
    "buk_provision_gratificacion",
    "buk_provision_bonificacion_gratificacion",
    "buk_provision_cts",
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    date_mm = I18n.l(date, format: "%m")
    date_yyyy_mm_dd = I18n.l(date, format: "%y%m%d")
    date_mm_yyyy = I18n.l(date, format: "%m/%Y")
    date_mm_yyyy_two = I18n.l(date, format: "%m/%y")

    obj_contabilidad = descartar_informativos(obj_contabilidad)

    data = {}
    grouped = obj_contabilidad.group_by{|l| l.cuenta_custom_attrs['Tipo de Asiento'] || 'Sin Clasificar'}

    grouped.each do |k, obj|
      libro_cc, libro_cd, libro_can = get_centralizaciones(empresa, obj, date_mm, date_yyyy_mm_dd, date_mm_yyyy_two, date_mm_yyyy)
      generate_datos(libro_cc, libro_cd, libro_can, k, data)
    end
    data
  end

  def generate_centra_cc(empresa, obj, date_mm, date_yyyy_mm_dd)
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    Exportador::BaseXlsx.crear_encabezado(sheet, ENCABEZADO_1, 0)
    total_deber = obj.select(&:deber?).sum(&:monto)

    agrupador = obj.group_by do |l|
      {
        cod_sub: "35#{empresa.custom_attrs["Código Subdiario Empresa"]}",
        cod_compro: "#{date_mm}00#{search_nota(l)} ",
        glosa: search_glosa(l),
      }
    end

    excel_data = agrupador.lazy.map do |k, _v|
      [
        k[:cod_sub],
        k[:cod_compro],
        date_yyyy_mm_dd,
        "MN",
        "F",
        "0",
        k[:glosa],
        total_deber,
        "V",
        "S",
        "010101",
        nil,
        nil,
        nil,
      ]
    end

    Exportador::BaseXlsx.escribir_celdas sheet, excel_data, offset: 1, number_format: "###0.00"
    Exportador::BaseXlsx.autofit sheet, [ENCABEZADO_1]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def generate_centra_cd(empresa, obj, date_mm, date_yyyy_mm_dd, date_mm_yyyy_two, date_mm_yyyy)
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    Exportador::BaseXlsx.crear_encabezado(sheet, ENCABEZADO_2, 0)

    agrupador = obj.group_by do |l|
      {
        cod_sub: "35#{l.area_custom_attrs["Código Subdiario"]}",
        cod_compro: "#{date_mm}00#{search_nota(l)} ",
        cod_cuenta: l.cuenta_contable,
        n_documento: search_numero_documento(l),
        n_ceco: show_cenco(l),
        cod_dh: l.cuenta_custom_attrs["D/H"],
        glosa: l.cuenta_custom_attrs["Descripción Concepto"],
      }
    end

    excel_data = agrupador.map.with_index(1) do |(k, v), index|
      [
        k[:cod_sub],
        k[:cod_compro],
        index.to_s.rjust(3, '0'),
        date_yyyy_mm_dd,
        k[:cod_cuenta],
        k[:n_documento],
        k[:n_ceco],
        "MN",
        k[:cod_dh],
        v.sum(&:monto),
        "PL",
        date_mm_yyyy,
        date_yyyy_mm_dd,
        date_yyyy_mm_dd,
        "0",
        "S",
        k[:glosa],
        date_mm_yyyy_two,
        "0",
        "0.00",
        nil,
        nil,
        "01/01/1900",
        "0",
        "0",
      ]
    end

    Exportador::BaseXlsx.escribir_celdas sheet, excel_data, offset: 1, number_format: "###0.00"
    Exportador::BaseXlsx.autofit sheet, [ENCABEZADO_2]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def generate_centra_can(empresa, obj)
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    Exportador::BaseXlsx.crear_encabezado(sheet, ENCABEZADO_3, 0)

    agrupador = obj.group_by do |l|
      {
        glosa: l.cuenta_custom_attrs["Glosa Detalle"],
        n_doc: l.numero_documento&.humanize,
        full_name: l.employee.nombre_completo,
        name_division: l.division_name,
        last_name: l.last_name,
        second_last_name: l.second_last_name,
        name: l.first_name,
      }
    end

    excel_data = agrupador.lazy.map do |k, _v|
      [
        "T",
        k[:n_doc],
        k[:full_name],
        k[:name_division],
        nil,
        nil,
        "V",
        "N",
        k[:last_name],
        k[:second_last_name],
        k[:name],
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        "0",
      ]
    end

    Exportador::BaseXlsx.escribir_celdas sheet, excel_data, offset: 1, number_format: "###0.00"
    Exportador::BaseXlsx.autofit sheet, [ENCABEZADO_3]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end
  private

    def search_nota obj
      case obj.cuenta_custom_attrs["Tipo de Asiento"]
      when "NOMINA"
        "11"
      when "LIQUIDACION"
        "12"
      when "PROV CTS"
        "15"
      when "PROV GRAT"
        "14"
      when "PROV VAC"
        "13"
      when "CTS"
        "16"
      end
    end

    def search_glosa obj
      case obj.cuenta_custom_attrs["Tipo de Asiento"]
      when "NOMINA"
        "Asiento Planilla Remuneraciones"
      when "LIQUIDACION"
        "Asiento Planilla Liquidaciones"
      when "PROV CTS"
        "Provisión de CTS"
      when "PROV GRAT"
        "Provisión de Gratificación"
      when "PROV VAC"
        "Provisión de Vacaciones"
      when "CTS"
        "CTS"
      end
    end

    def get_centralizaciones empresa, obj, date_mm, date_yyyy_mm_dd, date_mm_yyyy_two, date_mm_yyyy
      libro_cc = generate_centra_cc(empresa, obj, date_mm, date_yyyy_mm_dd)
      libro_cd = generate_centra_cd(empresa, obj, date_mm, date_yyyy_mm_dd, date_mm_yyyy_two, date_mm_yyyy)
      libro_can = generate_centra_can(empresa, obj)
      [libro_cc, libro_cd, libro_can]
    end

    def generate_datos libro_cc, libro_cd, libro_can, k, data
      data["libro_cc#{k}"] = Exportador::Contabilidad::AccountingFile.new(contents: libro_cc, name_formatter: -> (name) {"CC #{k} #{name}"})
      data["libro_cd#{k}"] = Exportador::Contabilidad::AccountingFile.new(contents: libro_cd, name_formatter: -> (name) {"CD #{k} #{name}"})
      data["libro_can#{k}"] = Exportador::Contabilidad::AccountingFile.new(contents: libro_can, name_formatter: -> (name) {"CAN #{k} #{name}"})
    end

    def descartar_informativos(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_INFORMATIVOS.include?(l.item_code)
      end
    end
end

# EXAMPLE 61
#draeger.rb


# frozen_string_literal: true

#Clase para la centralizacion personalizada cliente Draeger
class Exportador::Contabilidad::Peru::Personalizadas::Draeger < Exportador::Contabilidad
  include ContabilidadPeruHelper
  def initialize
    super()
    @extension = 'xlsx'
  end

  CABECERA = [
    'Journal Template Name',
    'Line No',
    'Journal Batch Name',
    'Account Type',
    'Account No',
    'Posting Date',
    'Document Date',
    'Document No',
    'Description',
    'Bal  Account No',
    'Currency Code',
    'Amount',
    'Debit Amount',
    'Credit Amount',
    'Posting Group',
    'Cod. dim. acceso dir. 1',
    'Source Code',
    'Bal  Account Type',
    'Destination Type',
  ].freeze

  def generate_doc(_empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    obj_contabilidad.group_by{|obj| obj.cuenta_custom_attrs['Tipo de asiento'] || ''}.map do |k, v|
      libro = excel_data(variable, v, k)
      ["file_#{k}", Exportador::Contabilidad::AccountingFile.new(contents: libro, name_formatter: -> (name) {"#{name} - #{k.presence || 'sin categoría'}"})]
    end.to_h
  end

  def excel_data(variable, obj_contabilidad, tipo_asiento)
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, tipo_asiento
    Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA, 0)

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    last_day = I18n.l(date, format: "%d/%m/%Y")

    agrupado = obj_contabilidad.group_by do |obj|
      {
        glosa: obj.glosa,
        deber_haber: obj.deber_o_haber,
        cenco: search_cc(obj),
        cuenta: obj.cuenta_contable,
      }
    end

    data = agrupado.map.with_index(1) do |(k, v), index|
      [
        "GENERAL",
        "#{index}0000",
        "PLANILLA",
        "cuenta",
        k[:cuenta],
        last_day,
        last_day,
        "PLANILLA EMPLEADOS",
        k[:glosa].to_s.upcase,
        nil,
        nil,
        k[:deber_haber] == "D" ? v.sum(&:monto) : v.sum(&:monto) * -1,
        k[:deber_haber] == "D" ? v.sum(&:monto) : 0,
        k[:deber_haber] == "C" ? v.sum(&:monto) : 0,
        nil,
        k[:cenco],
        "GENJNL",
        nil,
        nil,
      ]
    end
    Exportador::BaseXlsx.autofit sheet, [CABECERA]
    Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 1, number_format: "###,###,##0.00"
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end
end

# EXAMPLE 62
#ander.rb


# frozen_string_literal: true

# Archivo de Centralizacion Personalizada cliente Anders
class Exportador::Contabilidad::Peru::Personalizadas::Ander < Exportador::Contabilidad::Peru::CentralizacionContable
  include ContabilidadPeruHelper
  def initialize
    super()
    @extension = 'xlsx'
  end

  FIRST_HEADER = [
    'JdtNum',
    'DueDate',
    'Memo',
    'ProjectCode',
    'Reference2',
    'ReferenceDate',
    'Reference',
    'Taxdate',
    'Transactioncode',
  ].freeze

  SECOND_HEADER = [
    'RecordKey',
    'Fecha de Vencimiento',
    'Glosa  del Asiento',
    'Codigo de Proyecto',
    'Referencia del Asiento 2',
    'Fecha de contabilizacion',
    'Referencia del asiento',
    'Fecha de contabilizacion',
    'Codigo de Transaccion',
  ].freeze

  FIRST_HEADER_DETAIL = [
    'RecordKey',
    'LineNum',
    'AccountCode',
    'Shortname',
    'Debit',
    'Credit',
    'FCDebit',
    'FCCredit',
    'FCCurrency',
    'DueDate',
    'LineMemo',
    'Reference2',
    'TaxDate',
    'CostingCode1',
    'CostingCode2',
    'CostingCode3',
    'CostingCode4',
    'CostingCode5',
  ].freeze

  SECOND_HEADER_DETAIL = [
    'RecordKey',
    'LineNum',
    'AccountCode',
    'Shortname',
    'Debit',
    'Credit',
    'FCDebit',
    'FCCredit',
    'FCCurrency',
    'DueDate',
    'LineMemo',
    'Reference2',
    'TaxDate',
    'Centro de Costo 1',
    'Centro de Costo 2',
    'Centro de Costo 3',
    'Centro de Costo 4',
    'Centro de Costo 5',
  ].freeze

  NO_CONTABILIZAR_INFORMATIVOS = [
    "buk_sctr_pension",
    "sctr pension_debe",
    "sctr pension_haber",
    "buk_sctr_salud",
    "sctr salud_debe",
    "sctr salud_haber",
    "buk_vida_ley",
    "vida ley_debe",
    "vida ley_haber",
    'buk_provision_bonificacion_gratificacion',
    'provision_bonificacion_extraordinaria_gratificacion_deber',
    'provision_bonificacion_extraordinaria_gratificacion_haber',
    'buk_provision_cts',
    'provision_cts_deber',
    'provision_cts_haber',
    'buk_provision_vacaciones',
    'provision_vacaciones_deber',
    'provision_vacaciones_haber',
    'buk_provision_gratificacion',
    'provision_gratificacion_deber',
    'provision_gratificacion_haber',
  ].freeze

  def generate_doc empresa, variable, obj_contabilidad
    return unless obj_contabilidad.present?

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    fecha = date.strftime('%Y%m%d')
    mes_anio = I18n.l(date, format: '%B %Y')

    obj_contabilidad = descartar_informativos(obj_contabilidad)
    obj_contabilidad_practicantes = obj_contabilidad.select{|l| Job::Peru::CONTRATOS_PRACTICA.include?(l.tipo_contrato) && l.cuenta_custom_attrs['Código del Tipo de Asiento'] != "3"}
    obj_contabilidad = obj_contabilidad.reject{|l| Job::Peru::CONTRATOS_PRACTICA.include?(l.tipo_contrato) && l.cuenta_custom_attrs['Código del Tipo de Asiento'] != "3"}

    obj_contabilidad_agrupado = obj_contabilidad.group_by{|l| l.cuenta_custom_attrs["Tipo de Asiento"] || "Sin asiento"}
    libro = {}

    libro = obj_contabilidad_agrupado.map do |asiento, obj_asiento|
      [asiento.to_sym, Exportador::Contabilidad::AccountingFile.new(contents: excel_header(obj_asiento, empresa, fecha, asiento, mes_anio), name_formatter: -> (name) { "#{name} #{asiento}-cabecera" })]
    end.to_h

    obj_contabilidad_agrupado.each do |asiento, obj_asiento|
      libro["#{asiento}-detalle".to_sym] = Exportador::Contabilidad::AccountingFile.new(contents: excel_detail(obj_asiento, variable, empresa, fecha, asiento, mes_anio), name_formatter: -> (name) { "#{name}-#{asiento}-detalle" })
    end

    if obj_contabilidad_practicantes.present?
      libro[:practicantes_cabecera] = Exportador::Contabilidad::AccountingFile.new(contents: excel_header(obj_contabilidad_practicantes, empresa, fecha, 'Planilla de Practicantes', mes_anio),
                                                                                   name_formatter: -> (name) { "#{name} Planilla de Practicantes-cabecera" },)
      libro[:practicantes_detalle] = Exportador::Contabilidad::AccountingFile.new(contents: excel_detail(obj_contabilidad_practicantes, variable, empresa, fecha, 'Planilla de Practicantes', mes_anio),
                                                                                  name_formatter: -> (name) { "#{name} Planilla de Practicantes-detalle" },)
    end
    libro
  end

  def excel_header obj_contabilidad, empresa, fecha, asiento, mes_anio
    return unless obj_contabilidad.present?

    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    Exportador::BaseXlsx.crear_encabezado(sheet, FIRST_HEADER, 0)
    Exportador::BaseXlsx.crear_encabezado(sheet, SECOND_HEADER, 1)

    group_header = obj_contabilidad.group_by do |l|
      {
        recordkey: l.cuenta_custom_attrs['Código del Tipo de Asiento'],
        glosa_asiento: get_glosa(asiento, mes_anio),
      }
    end

    data = group_header.lazy.map do |k, _v|
      [
        k[:recordkey],
        fecha,
        k[:glosa_asiento],
        nil,
        k[:glosa_asiento],
        fecha,
        nil,
        fecha,
      ]
    end
    Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 2
    Exportador::BaseXlsx.autofit sheet, [FIRST_HEADER]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def excel_detail obj_contabilidad, _variable, empresa, fecha, asiento, mes_anio
    return unless obj_contabilidad.present?

    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    Exportador::BaseXlsx.crear_encabezado(sheet, FIRST_HEADER_DETAIL, 0)
    Exportador::BaseXlsx.crear_encabezado(sheet, SECOND_HEADER_DETAIL, 1)

    group = obj_contabilidad.group_by do |l|
      cenco1, cenco2, cenco3, cenco4, cenco5 = get_cenco(l)
      {
        recordkey: l.cuenta_custom_attrs['Código del Tipo de Asiento'],
        account: search_account(l),
        account_name: get_account_name(l),
        glosa_asiento: get_glosa(asiento, mes_anio),
        costing_code1: cenco1,
        deber_o_haber: l.deber_o_haber,
        costing_code2: cenco2,
        costing_code3: cenco3,
        costing_code4: cenco4,
        costing_code5: cenco5,
      }
    end

    data = group.map.with_index do |(k, v), index|
      [
        k[:recordkey],
        index.to_s,
        k[:account],
        nil,
        k[:deber_o_haber] == "D" ? v.sum(&:monto) : 0,
        k[:deber_o_haber] == "C" ? v.sum(&:monto) : 0,
        nil,
        nil,
        nil,
        nil,
        k[:account_name],
        k[:glosa_asiento],
        fecha,
        k[:costing_code1],
        k[:costing_code2],
        k[:costing_code3],
        k[:costing_code4],
        k[:costing_code5],
      ]
    end
    Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 2, number_format: "###0.00"
    Exportador::BaseXlsx.autofit sheet, [FIRST_HEADER_DETAIL]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def generate_data(_empresa, variable, obj_contabilidad, **_args)
    return {} unless obj_contabilidad.present?

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    fecha = date.strftime('%Y%m%d')
    mes_anio = I18n.l(date, format: '%B %Y')

    obj_contabilidad = descartar_informativos(obj_contabilidad)

    group_header = obj_contabilidad.group_by do |l|
      {
        recordkey: l.cuenta_custom_attrs['Código del Tipo de Asiento'],
        glosa_asiento: get_glosa(l.cuenta_custom_attrs['Tipo de Asiento'], mes_anio),
      }
    end

    header_data = group_header.lazy.map do |k, _v|
      {
        jdt_num: k[:recordkey],
        due_date: fecha,
        memo: k[:glosa_asiento],
        project_code: nil,
        reference2: k[:glosa_asiento],
        reference_date: fecha,
        reference: nil,
        tax_date: fecha,
        transaction_code: nil,
      }
    end

    group_detail = obj_contabilidad.group_by do |l|
      {
        recordkey: l.cuenta_custom_attrs['Código del Tipo de Asiento'],
        account: search_account(l),
        account_name: get_account_name(l),
        glosa_asiento: get_glosa(l.cuenta_custom_attrs['Tipo de Asiento'], mes_anio),
        centro_costo: l.centro_costo,
        deber_o_haber: l.deber_o_haber,
      }
    end

    detail_data = group_detail.map.with_index do |(k, v), index|
      {
        record_key: k[:recordkey],
        line_num: index,
        account_code: k[:account],
        short_name: nil,
        debit: k[:deber_o_haber] == "D" ? format("%#.2f", v.sum(&:monto)) : 0,
        credit: k[:deber_o_haber] == "C" ? format("%#.2f", v.sum(&:monto)) : 0,
        fc_debit: nil,
        fc_credit: nil,
        fc_currency: nil,
        due_date: nil,
        line_memo: k[:account_name],
        reference2: k[:glosa_asiento],
        tax_date: fecha,
        costing_code1: k[:centro_costo],
        costing_code2: nil,
        costing_code3: nil,
        costing_code4: nil,
        costing_code5: nil,
      }
    end
    header_data + detail_data
  end

  private
    def get_glosa asiento, mes_anio
      "#{asiento} - #{mes_anio}".upcase
    end

    def get_account_name obj
      obj.cuenta_custom_attrs["AFP"].to_s.casecmp("si").zero? ? search_name_afp(obj.afp).to_s.upcase : obj.glosa.upcase
    end

    def descartar_informativos(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_INFORMATIVOS.include?(l.nombre_cuenta)
      end
    end

    def get_cenco(obj)
      cenco_type = obj.centro_costo_custom_attrs&.dig("Columna contabilidad").to_s
      (1..5).map do |i|
        obj.centro_costo if cenco_type == "CostingCode#{i}"
      end
    end
end

# EXAMPLE 63
#vesper.rb


# frozen_string_literal: true

#
# clase para generar centralizacion contable personalizada para vesper
class Exportador::Contabilidad::Peru::Personalizadas::Vesper < Exportador::Contabilidad::Peru::CentralizacionContable

  NO_CONTABILIZAR_INFORMATIVOS = [
    "buk_vida_ley",
  ].freeze

  NO_CONTABILIZAR_CUENTAS = [
    "buk_eps_deber",
    "buk_eps_haber",
  ].freeze

  def generate_data(empresa, variable, obj_contabilidad, **_args)
    return {} unless obj_contabilidad.present? && empresa.custom_attrs["habilitado_api"].to_s.casecmp("si").zero?

    obj_contabilidad = descartar_informativos(obj_contabilidad)
    obj_contabilidad = descartar_cuentas(obj_contabilidad)

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    date_ddmmyyyy = date.strftime('%d/%m/%Y')
    date_month = I18n.l(date, format: '%B').upcase
    date_year = date.strftime('%Y')
    date_month_2 = date.strftime('%m')

    agrupador = data_agrupada(empresa, obj_contabilidad, date_month, date_year, date_month_2)

    agrupador.map do |k, v|
      [
        fecha: date_ddmmyyyy,
        entidad: k[:entidad],
        type_doc_employee: k[:type_doc_employee],
        n_doc_employee: k[:n_doc_employee],
        employee: k[:employee],
        account: k[:account],
        debit: k[:lado] == "D" ? v.sum(&:monto) : 0,
        credit: k[:lado] == "C" ? v.sum(&:monto) : 0,
        analytic: k[:analytic],
        description_line: k[:description_line],
        description_global: k[:description_global],
        num_comp: k[:num_comp],
      ]
    end
  end

  private

    def data_agrupada empresa, obj, date_month, date_year, date_month_2
      obj.group_by do |l|
        nombre = get_rut_nombre(l)
        {
          entidad: empresa.rut&.humanize,
          type_doc_employee: l.employee.document_type,
          n_doc_employee: tipo_doc(l),
          employee: nombre,
          account: l.cuenta_contable,
          lado: l.deber_o_haber,
          analytic: search_cc(l),
          description_line: show_glosa(l),
          description_global: get_glosa(l, date_month, date_year),
          num_comp: get_comprobante(l, date_month_2, date_year),
        }
      end
    end

    def tipo_doc l
      afp = l.afp.upcase
      return l.cuenta_custom_attrs&.dig(afp) if l.cuenta_custom_attrs["AFP"].to_s.casecmp("SI").zero?
      numero_documento = l.cuenta_custom_attrs["Mostrar DNI"].to_s.casecmp("si")&.zero? ? l.numero_documento.to_s : nil

      l.cuenta_custom_attrs["Agrupador"].to_s.casecmp("DNI").zero? ? numero_documento : l.tipo_doc.presence
    end

    def show_glosa l
      afp = l.afp.upcase
      l.cuenta_custom_attrs&.dig(afp).present? ? search_name_afp(afp) : l.glosa
    end

    def get_rut_nombre obj
      return nil unless obj.cuenta_custom_attrs["Agrupador"].to_s.casecmp("DNI").zero?
      obj.employee.apellidos_nombre.upcase if obj.cuenta_custom_attrs["mostrar_documento"].to_s.casecmp("Si").zero?
    end

    def get_glosa obj, date_month, date_year
      asiento = obj.cuenta_custom_attrs['Tipo de Asiento'].presence || 'Otros'
      "#{asiento} #{date_month} #{date_year}"
    end

    def get_comprobante obj, date_month_2, date_year
      comprobante = obj.cuenta_custom_attrs["Num_comp"]
      "#{comprobante}#{date_month_2}#{date_year}"
    end

    def descartar_informativos(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_INFORMATIVOS.include?(l.item_code)
      end
    end

    def descartar_cuentas(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_CUENTAS.include?(l.nombre_cuenta)
      end
    end
end

# EXAMPLE 64
#contabilidad_attach.rb


# frozen_string_literal: true

# Archivo de Centralizacion Personalizada cliente Contabilidad Attach
class Exportador::Contabilidad::Peru::Personalizadas::ContabilidadAttach < Exportador::Contabilidad
  include ContabilidadPeruHelper
  def initialize
    super()
    @extension = 'xlsx'
  end

  CABECERA = [
    'CUENTA CONTABLE',
    'DESCRIPCIÓN CONCEPTO',
    'CENTRO DE COSTO',
    'VALOR DEBE',
    'VALOR HABER',
    'NÚMERO DOCUMENTO',
    'NOMBRE COMPLETO',
  ].freeze

  ASIENTO = [
    'Planillas',
    'Provisiones',
    'No contabilizar',
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    obj_planilla = obj_contabilidad.select{|o| o.cuenta_custom_attrs&.dig('Archivo') == 'Planillas'}
    obj_provisiones = obj_contabilidad.select{|o| o.cuenta_custom_attrs&.dig('Archivo') == 'Provisiones'}
    obj_no_contabilizar = obj_contabilidad.select{|o| o.cuenta_custom_attrs&.dig('Archivo') == 'No contabilizar'}
    obj_sin_asiento = obj_contabilidad.reject do |o|
      ASIENTO.include?(o.cuenta_custom_attrs&.dig('Archivo'))
    end

    data_planilla = excel_data(obj_planilla, variable, empresa)
    data_provisiones = excel_data(obj_provisiones, variable, empresa)
    data_no_contabilizar = excel_data(obj_no_contabilizar, variable, empresa)

    archivos = {
      planilla: Exportador::Contabilidad::AccountingFile.new(contents: data_planilla, name_formatter: -> (name) {"#{name} PLANILLA"}),
      provisiones: Exportador::Contabilidad::AccountingFile.new(contents: data_provisiones, name_formatter: -> (name) {"#{name} PROVISIONES"}),
      no_contabilizar: Exportador::Contabilidad::AccountingFile.new(contents: data_no_contabilizar, name_formatter: -> (name) {"#{name} NO CONTABILIZAR"}),
    }

    if obj_sin_asiento.present?
      data_sin_asiento = excel_data(obj_sin_asiento, variable, empresa)
      archivos[:sin_asiento] = Exportador::Contabilidad::AccountingFile.new(contents: data_sin_asiento, name_formatter: -> (name) {"#{name} NO CATEGORIZADO"})
    end
    archivos
  end

  def excel_data(obj_contabilidad, _variable, empresa)
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA, 0)
    Exportador::BaseXlsx.autofit sheet, [CABECERA]

    agrupador = obj_contabilidad.group_by do |l|
      {
        cuenta_contable: get_cuenta(l),
        descripcion: get_descripcion(l),
        deber_o_haber: l.deber_o_haber,
        metodo_documento: get_documento(l),
        cencos: centro_costo(l),
        numero_documento: dni(l),
      }
    end
    excel_data = agrupador.map do |k, v|
      [
        k[:cuenta_contable],
        k[:descripcion],
        k[:cencos],
        k[:deber_o_haber] == "D" ? v.sum(&:monto) : 0,
        k[:deber_o_haber] == "C" ? v.sum(&:monto) : 0,
        k[:numero_documento],
        k[:metodo_documento],
      ]
    end

    Exportador::BaseXlsx.escribir_celdas sheet, excel_data, offset: 1, number_format: "###0"
    Exportador::BaseXlsx.formatear_columna(sheet, excel_data, [2, 3], "#,##0.00")
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  private
    def get_descripcion object
      consolidar = object.cuenta_custom_attrs&.dig("Consolidar")&.parameterize
      return object.glosa unless consolidar.present?
      return object.afp if consolidar == "afp"
      consolidar
    end

    def get_documento object
      nombre_completo = "#{object.last_name} #{object.second_last_name} #{object.first_name}"
      nombre_completo if object.cuenta_custom_attrs["Agrupador"] == "DNI"
    end

    def dni object
      object.numero_documento if object.cuenta_custom_attrs["DNI"] == "SI"
    end

    def get_cuenta object
      consolidar = object.cuenta_custom_attrs&.dig("Consolidar")&.parameterize
      return object.cuenta_contable unless consolidar == "afp"
      object.cuenta_custom_attrs&.dig(object.afp)
    end

    def centro_costo object
      object.centro_costo if object.cuenta_custom_attrs["Incluir Centro Costo"] == "SI"
    end
end

# EXAMPLE 65
#megas_gas_sac.rb


# frozen_string_literal: true

#
#Exportador de comprobante contable para MegasGasSac
class Exportador::Contabilidad::Peru::Personalizadas::MegasGasSac < Exportador::Contabilidad::Peru::CentralizacionContable
  def initialize
    super()
    @extension = 'xlsx'
  end

  CABECERA_UNO = [
    'Memo',
    'ReferenceDate',
    'DueDate',
    'TaxDate',
    'Reference',
    'Reference2',
    'JournalEntryLines',
  ].freeze

  CABECERA_DOS = [
    'Memo',
    'RefDate',
    'AutoVAT',
    'TaxDate',
    'Ref1',
    'Ref2',
    'JournalEntryLines',
  ].freeze

  TITULOS_UNO = [
    'Line_ID',
    'AccountCode',
    'ShortName',
    'Debit',
    'Credit',
    'FCCurrency',
    'FCDebit',
    'FCCredit',
    'LineMemo',
    'Reference1',
    'Reference2',
    'CostingCode',
    'CostingCode2',
    'CostingCode3',
    'CostingCode4',
    'CostingCode5',
    'ProjectCode',
    'U_SYP_INFOPE01',
    'U_SYP_INFOPE02',
  ].freeze

  TITULOS_DOS = [
    'LineNum',
    'Account',
    'ShortName',
    'Debit',
    'Credit',
    'FCCurrency',
    'FCDebit',
    'FCCredit',
    'LineMemo',
    'Ref1',
    'Ref2',
    'OcrCode',
    'OcrCode2',
    'OcrCode3',
    'OcrCode4',
    'OcrCode5',
    'Project',
    'U_SYP_INFOPE01',
    'U_SYP_INFOPE02',
  ].freeze

  NO_CONTABILIZAR_INFORMATIVOS = [
    "buk_provision_vacaciones",
    "buk_provision_gratificacion",
    "buk_provision_cts",
    "buk_provision_bonificacion_gratificacion",
    "provision_bonificacion_extraordinaria_gratificacion_deber",
    "provision_bonificacion_extraordinaria_gratificacion_haber",
    "provision_cts_deber",
    "provision_cts_haber",
    "provision_vacaciones_deber",
    "provision_vacaciones_haber",
    "provision_gratificacion_deber",
    "provision_gratificacion_haber",
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    month = I18n.l(date, format: '%B %Y').upcase
    end_date = date.strftime("%Y%m%d")
    quincena = date.strftime("%Y%m15")
    obj_contabilidad_custom = descartar_informativos(obj_contabilidad)

    grouped = obj_contabilidad_custom.group_by{|l| l.cuenta_custom_attrs&.dig('Tipo de Asiento') || ''}

    libros = {}
    grouped.each do |k, obj|
      concepto = k.upcase
      libro_cabecera = generate_cabecera(empresa, obj, concepto, month, end_date, quincena)
      libros["Libro_cabecera_#{k}".to_sym] = Exportador::Contabilidad::AccountingFile.new(contents: libro_cabecera, name_formatter: -> (name) {"CABECERA #{concepto} #{name}"})
      libro_cuerpo = generate_centralizacion(empresa, obj, "#{concepto} #{month}", month)
      libros["Libro_cuerpo_#{k}".to_sym] = Exportador::Contabilidad::AccountingFile.new(contents: libro_cuerpo, name_formatter: -> (name) {"#{concepto} #{name}"})
    end
    libros
  end

  def generate_cabecera(empresa, obj, tipo_doc, month, end_date, quincena)
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA_UNO, 0)
    Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA_DOS, 1)
    ref = obj.map{ |l| l.cuenta_custom_attrs&.dig("Código del Tipo de Asiento")}.uniq.join("-")
    data = [
      "#{tipo_doc} #{month}",
      fecha_tipoasiento(tipo_doc, end_date, quincena),
      fecha_tipoasiento(tipo_doc, end_date, quincena),
      fecha_tipoasiento(tipo_doc, end_date, quincena),
      nil,
      "#{ref} #{month}",
    ]
    Exportador::BaseXlsx.escribir_celdas sheet, [data], offset: 2, number_format: '###0'
    Exportador::BaseXlsx.autofit sheet, [CABECERA_UNO]
    Exportador::BaseXlsx.autofit sheet, [CABECERA_DOS]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def generate_centralizacion(empresa, obj_contabilidad, tipo_doc, month)
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    Exportador::BaseXlsx.crear_encabezado(sheet, TITULOS_UNO, 0)
    Exportador::BaseXlsx.crear_encabezado(sheet, TITULOS_DOS, 1)

    agrupador = obj_contabilidad.group_by do |l|
      orcode, orcode1, orcode2, orcode3 = get_centro_costo(l)
      {
        cuenta: search_account(l),
        nro_doc: get_shortname(l),
        orcode: orcode,
        orcode1: orcode1,
        orcode2: orcode2,
        orcode3: orcode3,
        deber_haber: l.deber_o_haber,
        codigo: l.cuenta_custom_attrs&.dig("Código del Tipo de Asiento"),
      }
    end

    data = agrupador.map.with_index(0) do |(k, v), index|
      validador_nro_doc = k[:nro_doc].present? ? "E#{k[:nro_doc].to_s.rjust(11, '0')}" : nil
      [
        index.to_s,
        k[:cuenta],
        validador_nro_doc,
        k[:deber_haber] == "D" ? v.sum(&:monto) : 0,
        k[:deber_haber] == "C" ? v.sum(&:monto) : 0,
        nil,
        nil,
        nil,
        tipo_doc,
        nil,
        "#{k[:codigo]} #{month}",
        k[:orcode],
        k[:orcode1],
        k[:orcode2],
        k[:orcode3],
      ]
    end
    Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 2, number_format: '###0.00'
    Exportador::BaseXlsx.autofit sheet, [TITULOS_UNO]
    Exportador::BaseXlsx.autofit sheet, [TITULOS_DOS]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  def generate_data(_empresa, variable, obj_contabilidad, **_args)
    return [] if obj_contabilidad.nil? || obj_contabilidad.empty?

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    month = I18n.l(date, format: '%B %Y').upcase
    end_date = date.strftime("%Y%m%d")
    quincena = date.strftime("%Y%m15")

    data = []

    obj_contabilidad_custom = descartar_informativos(obj_contabilidad)

    grouped = obj_contabilidad_custom.group_by{|l| l.cuenta_custom_attrs&.dig('Tipo de Asiento') || ''}

    grouped.each do |k, obj|
      concepto = k.upcase
      data << generate_api_cuerpo(obj, month, end_date, concepto, quincena)
    end
    data
  end

  private
    def descartar_informativos(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_INFORMATIVOS.include?(l.nombre_cuenta)
      end
    end

    def generate_api_cuerpo(obj_contabilidad, month, end_date, tipo_asiento, quincena)
      ref = obj_contabilidad.map{ |l| l.cuenta_custom_attrs["Código del Tipo de Asiento"]}.uniq.join("-")

      data_header = {
        Memo: "#{tipo_asiento} #{month}",
        ReferenceDate: fecha_tipoasiento(tipo_asiento, end_date, quincena),
        DueDate: fecha_tipoasiento(tipo_asiento, end_date, quincena),
        TaxDate: fecha_tipoasiento(tipo_asiento, end_date, quincena),
        Reference: fecha_tipoasiento(tipo_asiento, end_date, quincena),
        Reference2: "#{ref} #{month}",
        JournalEntryLines: nil,
      }

      agrupador = obj_contabilidad.group_by do |k|
        orcode, orcode1, orcode2, orcode3 = get_centro_costo(k)
        {
          cuenta: search_account(k),
          nro_doc: get_shortname(k),
          orcode: orcode,
          orcode1: orcode1,
          orcode2: orcode2,
          orcode3: orcode3,
          deber_haber: k.deber_o_haber,
          codigo: k.cuenta_custom_attrs["Código del Tipo de Asiento"].to_s.upcase,
          tipo_doc: k.cuenta_custom_attrs['Tipo de Asiento'].upcase,
        }
      end

      data_header[:JournalEntryLines] = agrupador.map.with_index do |(k, v), index|
        validador_nro_doc = k[:nro_doc].present? ? "E#{k[:nro_doc].to_s.rjust(11, '0')}" : nil
        {
          Line_ID: index,
          AccountCode: k[:cuenta],
          ShortName: validador_nro_doc,
          Debit: k[:deber_haber] == "D" ? format("%#.2f", v.sum(&:monto)) : 0,
          Credit: k[:deber_haber] == "C" ? format("%#.2f", v.sum(&:monto)) : 0,
          FCCurrency: nil,
          FCDebit: nil,
          FCCredit: nil,
          LineMemo: "#{k[:tipo_doc]} #{month}",
          Reference1: nil,
          Reference2: "#{k[:codigo]} #{month}",
          CostingCode: k[:orcode],
          CostingCode2: k[:orcode1],
          CostingCode3: k[:orcode2],
          CostingCode4: k[:orcode3],
          CostingCode5: nil,
          ProjectCode: nil,
          U_SYP_INFOPE01: nil,
          U_SYP_INFOPE02: nil,
        }
      end
      data_header
    end

    def get_centro_costo obj
      codigo = obj.centro_costo.to_s.split("-")
      return unless obj.cuenta_custom_attrs&.dig("OrCode").to_s.upcase.squish == "SI"
      [codigo[0], codigo[1], codigo[2], codigo[3]]
    end

    def get_shortname obj
      obj.numero_documento if obj.cuenta_custom_attrs["Agrupador"] == 'DNI'
    end

    def fecha_tipoasiento tipo_asiento, end_date, quincena
      tipo_asiento == "PRIMERA QUINCENA" ? quincena : end_date
    end
end

# EXAMPLE 66
#comtecsa.rb


# frozen_string_literal: true

# Archivo de Centralizacion Personalizada cliente Comtecsa del Perú
class Exportador::Contabilidad::Peru::Personalizadas::Comtecsa < Exportador::Contabilidad
  include ContabilidadPeruHelper
  def initialize
    super()
    @extension = 'xlsx'
  end

  HEADER = [
    'Sub Diario',
    'Número de Comprobante',
    'Fecha de Comprobante',
    'Código de Moneda',
    'Glosa Principal',
    'Tipo de Cambio',
    'Tipo de Conversión',
    'Flag de Conversión de Moneda',
    'Fecha Tipo de Cambio',
    'Cuenta Contable',
    'Código de Anexo',
    'Código de Centro de Costo',
    'Debe / Haber',
    'Importe Original',
    'Importe en Dólares',
    'Importe en Soles',
    'Tipo de Documento',
    'Número de Documento',
    'Fecha de Documento',
    'Fecha de Vencimiento',
    'Código de Area',
    'Glosa Detalle',
    'Código de Anexo Auxiliar',
    'Medio de Pago',
    'Tipo de Documento de Referencia',
    'Número de Documento Referencia',
    'Fecha Documento Referencia',
    'Nro Máq. Registradora Tipo Doc. Ref.',
    'Base Imponible Documento Referencia',
    'IGV Documento Provisión',
    'Tipo Referencia en estado MQ',
    'Número Serie Caja Registradora',
    'Fecha de Operación',
    'Tipo de Tasa',
    'Tasa Detracción/Percepción',
    'Importe Base Detracción/Percepción Dólares',
    'Importe Base Detracción/Percepción Soles',
    'Tipo Cambio para F',
    'Importe de IGV sin derecho crédito fiscal',
  ].freeze

  def generate_doc(_empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, "Centralización Contable"
    Exportador::BaseXlsx.crear_encabezado(sheet, HEADER, 0)

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    month = date.strftime("%m")
    date_ano = date.strftime("%m/%d/%Y")
    month_year = date.strftime("%m-%Y")
    number_cpbt = "#{month}0001"
    glosa_principal = "PLANILLA DE SUELDO - #{month}"

    excel_data = obj_contabilidad.sort_by(&:deber_o_haber).reverse.lazy.map do |l|
      [
        "35",
        number_cpbt,
        date_ano,
        "MN",
        glosa_principal,
        "",
        "M",
        "S",
        date_ano,
        l.cuenta_contable,
        ruc(l),
        centro_costo(l),
        l.deber_o_haber,
        l.monto,
        nil,
        nil,
        "PL",
        month_year,
        date_ano,
        nil,
        nil,
        l.glosa,
      ]
    end

    Exportador::BaseXlsx.escribir_celdas sheet, excel_data, offset: 1, number_format: "#,##0"
    Exportador::BaseXlsx.autofit sheet, [HEADER]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end
  private
    def centro_costo l
      l.cuenta_contable&.first == '6' ? l.centro_costo : nil
    end

    def ruc l
      search_ruc(l) unless l.cuenta_custom_attrs&.dig("RUC") == "VACIO"
    end
end

# EXAMPLE 67
#levis_peru.rb


# Archivo de Centralizacion Personalizada cliente Levis Perú
class Exportador::Contabilidad::Peru::Personalizadas::LevisPeru < Exportador::Contabilidad
  def initialize
    super()
    @extension = 'xlsx'
  end
  def create_lineas_liquidacion(liquidacions, **args)
    ::Contabilidad::Peru::LineasLiquidacionesService.new(liquidacions, **args)
  end
  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    #Hojas
    sheet1 = Exportador::BaseXlsx.crear_hoja book, "PLANILLA"
    sheet2 = Exportador::BaseXlsx.crear_hoja book, "PROVISION BONO ANUAL"
    sheet3 = Exportador::BaseXlsx.crear_hoja book, "PROVISION BBSS"
    sheet4 = Exportador::BaseXlsx.crear_hoja book, "LIQUIDACIONES"
    mes_anno_posterio = (variable.end_date + 1.month).latest_business_day(Location.country(empresa.country_namespace)).strftime('%m%Y')
    mes_procesado = (variable.end_date).latest_business_day(Location.country(empresa.country_namespace)).strftime('%m')
    fecha_proceso = variable.end_date.strftime("%d%m%Y")
    mes_str = I18n.l(variable.end_date.latest_business_day(Location.country(empresa.country_namespace)), format: '%B').upcase
    anio = variable.end_date.strftime('%Y')
    index = 1
    agrupado = ["CENCO", "TOTAL"]
    titulos =  ['Counter',
                'Co. Code',
                'Doc Date',
                'Post Date',
                'Posting Period',
                'Document Type',
                'Transaction Currency',
                'Ref No',
                'Doc Hdr Txt',
                'Payment Terms',
                'Pst Key',
                'GL Account',
                'Absolute Amount (TC)',
                'Cost Center',
                'WBS Element',
                'Internal Order',
                'Profit Center',
                'Trading Partner',
                'Transaction Type',
                'Assign Number',
                'Item Text',
                'Quantity',
                'Unit of Measure',
                'Special GL Indicator',
                'Reason for Reversal',
                'Planned Date for the Reverse Posting',
                'Alternative Recon Account',]
    Exportador::BaseXlsx.crear_encabezado(sheet1, titulos, 0)
    Exportador::BaseXlsx.crear_encabezado(sheet2, titulos, 0)
    Exportador::BaseXlsx.crear_encabezado(sheet3, titulos, 0)
    Exportador::BaseXlsx.crear_encabezado(sheet4, titulos, 0)
    group_planilla = metodo_agrupar(1, obj_contabilidad, mes_str, agrupado)
    excel_data = group_planilla.map do |k, v|
      print_agrupados(k, v, fecha_proceso, mes_anno_posterio, anio, mes_str, mes_procesado)
    end
    Exportador::BaseXlsx.escribir_celdas sheet1, excel_data, offset: index, number_format: '###0.00'
    index += 1
    metodo_imprimir_detalle(1, obj_contabilidad, mes_anno_posterio, mes_str, anio, index, fecha_proceso, sheet1, agrupado, mes_procesado)
    #--------------------------------------
    index = 1
    group_planilla = metodo_agrupar(2, obj_contabilidad, mes_str, agrupado)
    excel_data = group_planilla.map do |k, v|
      print_agrupados(k, v, fecha_proceso, mes_anno_posterio, anio, mes_str, mes_procesado)
    end
    Exportador::BaseXlsx.escribir_celdas sheet2, excel_data, offset: index, number_format: '###0.00'
    index += 1
    metodo_imprimir_detalle(2, obj_contabilidad, mes_anno_posterio, mes_str, anio, index, fecha_proceso, sheet2, agrupado, mes_procesado)
    #-----------------------------------------
    index = 1
    group_planilla = metodo_agrupar(3, obj_contabilidad, mes_str, agrupado)
    excel_data = group_planilla.map do |k, v|
      print_agrupados(k, v, fecha_proceso, mes_anno_posterio, anio, mes_str, mes_procesado)
    end
    Exportador::BaseXlsx.escribir_celdas sheet3, excel_data, offset: index, number_format: '###0.00'
    index += 1
    metodo_imprimir_detalle(3, obj_contabilidad, mes_anno_posterio, mes_str, anio, index, fecha_proceso, sheet3, agrupado, mes_procesado)
    #-----------------------------------------
    index = 1
    group_planilla = metodo_agrupar(4, obj_contabilidad, mes_str, agrupado)
    excel_data = group_planilla.map do |k, v|
      print_agrupados(k, v, fecha_proceso, mes_anno_posterio, anio, mes_str, mes_procesado)
    end
    Exportador::BaseXlsx.escribir_celdas sheet4, excel_data, offset: index, number_format: '###0.00'
    index += 1
    metodo_imprimir_detalle(4, obj_contabilidad, mes_anno_posterio, mes_str, anio, index, fecha_proceso, sheet4, agrupado, mes_procesado)
    Exportador::BaseXlsx.autofit(sheet1, [titulos])
    Exportador::BaseXlsx.autofit(sheet2, [titulos])
    Exportador::BaseXlsx.autofit(sheet3, [titulos])
    Exportador::BaseXlsx.autofit(sheet4, [titulos])
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end
  private
    def search_glosa hoja
      case hoja
      when 1
        "PLLA LEVIS"
      when 2
        "PROV. BONO AIP %"
      when 3
        "PROV. BB.SS"
      when 4
        "LIQUIDACION BB.SS"
      end
    end
    def search_glosa_u hoja, mes_str, obj
      array_glosa = {
        "provision_gratificacion_deber" => "GRT #{mes_str}",
        "provision_gratificacion_haber" => "GRT #{mes_str}",
        "provision_bonificacion_extraordinaria_gratificacion_deber" => "BON LEY GRT #{mes_str}",
        "provision_bonificacion_extraordinaria_gratificacion_haber" => "BON LEY GRT #{mes_str}",
        "provision_cts_deber" => "CTS #{mes_str}",
        "provision_cts_haber" => "CTS #{mes_str}",
        "provision_vacaciones_deber" => "VAC #{mes_str}",
        "provision_vacaciones_haber" => "VAC #{mes_str}",
      }
      case hoja
      when 1
        "PLLA LEVIS #{mes_str}"
      when 2
        "PROV. BONO ANUAL AIP #{mes_str}"
      when 3
        array_glosa[obj.nombre_cuenta]
      when 4
        "LIQUIDACIONES BB.SS #{mes_str}"
      end
    end
    def print_detalle l, hoja, fecha_proceso, mes_anno, mes_str, mes_procesado, anio
      [
        1.to_s, #A
        2000.to_s, #B
        fecha_proceso.to_s, #C
        fecha_proceso.to_s, #D
        mes_anno.to_s, #E
        "SA",
        "PEN",
        mes_str,
        search_glosa(hoja),
        nil,
        l.cuenta_custom_attrs&.dig("Clave Contabilización").to_s, #K
        l.cuenta_contable.to_s, #L
        l.deber_o_haber == "D" ? l.deber : l.haber,
        l.centro_costo,
        nil,
        nil,
        nil,
        nil,
        nil,
        "#{anio}#{mes_procesado}".to_s, #T
        search_glosa_u(hoja, mes_str, l),
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
      ]
    end
    def print_agrupados k, v, fecha_proceso, mes_anno, anio, mes_str, mes_procesado
      [
        1.to_s,
        2000.to_s,
        fecha_proceso.to_s,
        fecha_proceso.to_s,
        mes_anno.to_s,
        "SA",
        "PEN",
        mes_str,
        k[:glosa],
        nil,
        k[:clave_contabilizacion].to_s,
        k[:cuenta_contable].to_s,
        v.sum(&:monto),
        k[:centro_costo1],
        nil,
        nil,
        nil,
        nil,
        nil,
        "#{anio}#{mes_procesado}".to_s,
        k[:glosa2],
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
      ]
    end
    def search_cenco object
      object.centro_costo if object.cuenta_custom_attrs&.dig("Totalizada")&.upcase == "CENCO"
    end
    def metodo_agrupar hoja, obj_contabilidad, mes_str, agrupado
      array_asiento = {
        1 => "PLANILLA",
        2 => "PROVISION BONO ANUAL",
        3 => "PROVISION BBSS",
        4 => "LIQUIDACIONES",
      }
      asiento = obj_contabilidad.select{|o| o.cuenta_custom_attrs&.dig("Asiento Contable") == array_asiento[hoja] && agrupado.include?(o.cuenta_custom_attrs&.dig("Totalizada"))}
      asiento.group_by do |o|
        {
          glosa: search_glosa(hoja),
          clave_contabilizacion: o.cuenta_custom_attrs&.dig("Clave Contabilización"),
          cuenta_contable: o.cuenta_contable,
          deber_o_haber: o.deber_o_haber,
          centro_costo1: I18n.transliterate(search_cenco(o)),
          glosa2: search_glosa_u(hoja, mes_str, o),
        }
      end
    end
    def metodo_imprimir_detalle hoja, obj_contabilidad, mes_anno_posterio, mes_str, anio, index, fecha_proceso, sheet, agrupado, mes_procesado
      array_asiento = {
        1 => "PLANILLA",
        2 => "PROVISION BONO ANUAL",
        3 => "PROVISION BBSS",
        4 => "LIQUIDACIONES",
      }
      asiento_detalle = obj_contabilidad.select{|o| o.cuenta_custom_attrs&.dig("Asiento Contable") == array_asiento[hoja] && agrupado.exclude?(o.cuenta_custom_attrs&.dig("Totalizada"))}
      asiento_detalle.each do |p|
        data = print_detalle(p, hoja, fecha_proceso, mes_anno_posterio, mes_str, mes_procesado, anio)
        Exportador::BaseXlsx.escribir_celdas sheet, [data], offset: index, number_format: "#,##0"
        index += 1
      end
    end
end

# EXAMPLE 68
#black_llama_hostel.rb


# frozen_string_literal: true

#
# clase para generar centralizacion contable personalizada para black llama hostel
class Exportador::Contabilidad::Peru::Personalizadas::BlackLlamaHostel < Exportador::Contabilidad::Peru::CentralizacionContable
  def initialize
    super()
    @extension = 'xlsx'
  end

  CABECERA = [
    [
      "Campo",
      "Sub Diario",
      "Número de Comprobante",
      "Fecha de Comprobante",
      "Código de Moneda",
      "Glosa Principal",
      "Tipo de Cambio",
      "Tipo de Conversión",
      "Flag de Conversión de Moneda",
      "Fecha Tipo de Cambio",
      "Cuenta Contable",
      "Código de Anexo",
      "Código de Centro de Costo",
      "Debe / Haber",
      "Importe Original",
      "Importe en Dólares",
      "Importe en Soles",
      "Tipo de Documento",
      "Número de Documento",
      "Fecha de Documento",
      "Fecha de Vencimiento",
      "Código de Area",
      "Glosa Detalle",
      "Código de Anexo Auxiliar",
      "Medio de Pago",
      "Tipo de Documento de Referencia",
      "Número de Documento Referencia",
      "Fecha Documento Referencia",
      "Nro Máq. Registradora Tipo Doc. Ref.",
      "Base Imponible Documento Referencia",
      "IGV Documento Provisión",
      "Tipo Referencia en estado MQ",
      "Número Serie Caja Registradora",
      "Fecha de Operación",
      "Tipo de Tasa",
      "Tasa Detracción/Percepción",
      "Importe Base Detracción/Percepción Dólares",
      "Importe Base Detracción/Percepción Soles",
      "Tipo Cambio para 'F'",
      "Importe de IGV sin derecho crédito fiscal",
      "Tasa IGV",
    ],
    [
      "Restricciones",
      "Ver T.G. 02",
      "Los dos primeros dígitos son el mes y los otros 4 siguientes un correlativo",
      "",
      "Ver T.G. 03",
      "",
      "Llenar  solo si Tipo de Conversión es 'C'. Debe estar entre >=0 y <=9999.999999",
      "Solo: 'C'= Especial, 'M'=Compra, 'V'=Venta , 'F' De acuerdo a fecha",
      "Solo: 'S' = Si se convierte, 'N'= No se convierte",
      "Si  Tipo de Conversión 'F'",
      "Debe existir en el Plan de Cuentas",
      "Si Cuenta Contable tiene seleccionado Tipo de Anexo, debe existir en la tabla de Anexos",
      "Si Cuenta Contable tiene habilitado C. Costo, Ver T.G. 05",
      "'D' ó 'H'",
      "Importe original de la cuenta contable. Obligatorio, debe estar entre >=0 y <=99999999999.99",
      "Importe de la Cuenta Contable en Dólares. Obligatorio si Flag de Conversión de Moneda esta en 'N', debe estar entre >=0 y <=99999999999.99",
      "Importe de la Cuenta Contable en Soles. Obligatorio si Flag de Conversión de Moneda esta en 'N', debe estra entre >=0 y <=99999999999.99",
      "Si Cuenta Contable tiene habilitado el Documento Referencia Ver T.G. 06",
      "Si Cuenta Contable tiene habilitado el Documento Referencia Incluye Serie y Número",
      "Si Cuenta Contable tiene habilitado el Documento Referencia",
      "Si Cuenta Contable tiene habilitada la Fecha de Vencimiento",
      "Si Cuenta Contable tiene habilitada el Area. Ver T.G. 26",
      "",
      "Si Cuenta Contable tiene seleccionado Tipo de Anexo Referencia",
      "Si Cuenta Contable tiene habilitado Tipo Medio Pago. Ver T.G. 'S1'",
      "Si Tipo de Documento es 'NA' ó 'ND' Ver T.G. 06",
      "Si Tipo de Documento es 'NC', 'NA' ó 'ND', incluye Serie y Número",
      "Si Tipo de Documento es 'NC', 'NA' ó 'ND'",
      "Si Tipo de Documento es 'NC', 'NA' ó 'ND'. Solo cuando el Tipo Documento de Referencia 'TK'",
      "Si Tipo de Documento es 'NC', 'NA' ó 'ND'",
      "Si Tipo de Documento es 'NC', 'NA' ó 'ND'",
      "Si la Cuenta Contable tiene Habilitado Documento Referencia 2 y  Tipo de Documento es 'TK'",
      "Si la Cuenta Contable teien Habilitado Documento Referencia 2 y  Tipo de Documento es 'TK'",
      "Si la Cuenta Contable tiene Habilitado Documento Referencia 2. Cuando Tipo de Documento es 'TK', consignar la fecha de emision del ticket",
      "Si la Cuenta Contable tiene configurada la Tasa:  Si es '1' ver T.G. 28 y '2' ver T.G. 29",
      "Si la Cuenta Contable tiene conf. en Tasa:  Si es '1' ver T.G. 28 y '2' ver T.G. 29. Debe estar entre >=0 y <=999.99",
      "Si la Cuenta Contable tiene configurada la Tasa. Debe ser el importe total del documento y estar entre >=0 y <=99999999999.99",
      "Si la Cuenta Contable tiene configurada la Tasa. Debe ser el importe total del documento y estar entre >=0 y <=99999999999.99",
      "Especificar solo si Tipo Conversión es 'F'. Se permite 'M' Compra y 'V' Venta.",
      "Especificar solo para comprobantes de compras con IGV sin derecho de crédito Fiscal. Se detalle solo en la cuenta 42xxxx",
      "Obligatorio para comprobantes de compras, valores validos 0,10,18.",
    ],
    [
      "Tamaño/Formato",
      "4 Caracteres",
      "6 Caracteres",
      "dd/mm/aaaa",
      "2 Caracteres",
      "40 Caracteres",
      "Numérico 11, 6",
      "1 Caracteres",
      "1 Caracteres",
      "dd/mm/aaaa",
      "12 Caracteres",
      "18 Caracteres",
      "6 Caracteres",
      "1 Carácter",
      "Numérico 14,2",
      "Numérico 14,2",
      "Numérico 14,2",
      "2 Caracteres",
      "20 Caracteres",
      "dd/mm/aaaa",
      "dd/mm/aaaa",
      "3 Caracteres",
      "30 Caracteres",
      "18 Caracteres",
      "8 Caracteres",
      "2 Caracteres",
      "20 Caracteres",
      "dd/mm/aaaa",
      "20 Caracteres",
      "Numérico 14,2",
      "Numérico 14,2",
      "'MQ'",
      "15 caracteres",
      "dd/mm/aaaa",
      "5 Caracteres",
      "Numérico 14,2",
      "Numérico 14,2",
      "Numérico 14,2",
      "1 Caracter",
      "Numérico 14,2",
      "Numérico 14,2",
    ],
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    books = {}
    obj_contabilidad.group_by{|l| l.cuenta_custom_attrs&.dig('Tipo de asiento').presence || 'Otros'}.each do |k, obj|
      book = generate_book(empresa, variable, obj, k)
      books[k] = Exportador::Contabilidad::AccountingFile.new(contents: book, name: "#{empresa.nombre} - #{k}")
    end
    books
  end

  def generate_book(empresa, variable, obj_contabilidad, nombre_hoja)
    return unless obj_contabilidad.present?

    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    Exportador::BaseXlsx.autofit sheet, CABECERA
    Exportador::BaseXlsx.escribir_celdas sheet, CABECERA, offset: 0

    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    date_ddmmyyyy_dash = date.strftime('%d-%m-%Y')
    month = date.strftime('%m')
    date_ddmmyyyy_slash = date.strftime('%d/%m/%Y')
    date_mmmyyyy = I18n.l(date, format: '%B %Y')
    date_mmyyyy = date.strftime('%m%Y')
    glosa_principal = "#{nombre_hoja} #{date_mmmyyyy}".upcase
    tipo_cambio = kpi_dolar(variable.id, empresa.id, 'TC_contabilizar')

    obj_contabilidad = obj_contabilidad.group_by do |l|
      subdiario, correlativo, pl, anexo, cenco = get_atributos_afp(l)
      {
        sub_diario: subdiario,
        attr_correlativo: correlativo,
        tipo_doc: pl,
        cuenta_contable: search_account(l),
        cod_anexo: anexo,
        cencos: cenco,
        lado: l.deber_o_haber,
        glosa: search_glosa_afp(l).upcase,
      }
    end

    data = obj_contabilidad.lazy.map do |k, v|
      [
        nil,
        k[:sub_diario],
        "#{month}#{k[:attr_correlativo]}",
        date_ddmmyyyy_slash,
        "MN",
        glosa_principal,
        tipo_cambio,
        'V',
        'S',
        nil,
        k[:cuenta_contable],
        k[:cod_anexo],
        k[:cencos],
        k[:lado] == 'C' ? 'H' : 'D',
        v.sum(&:monto),
        nil,
        nil,
        k[:tipo_doc],
        k[:lado] == "C" ? date_mmyyyy : nil,
        date_ddmmyyyy_dash,
        nil,
        nil,
        k[:glosa],
      ]
    end

    Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 3, number_format: '#,##0.00'
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  private

    def get_atributos_afp obj
      return [obj.cuenta_custom_attrs['Sub Diario'], obj.cuenta_custom_attrs['Correlativo'], mostrar_pl(obj, false), get_anexo(obj, false), get_cenco(obj, false)] unless obj.cuenta_custom_attrs["AFP"].to_s.casecmp('si').zero?
      [afp_method(obj)&.custom_attrs&.dig("Sub Diario"), afp_method(obj)&.custom_attrs&.dig("Correlativo"), mostrar_pl(obj, true), get_anexo(obj, true), get_cenco(obj, true)]
    end

    def mostrar_pl obj, valor
      mostrar_pl = valor ? afp_method(obj)&.custom_attrs&.dig("Mostrar PL") : obj.cuenta_custom_attrs['Mostrar PL']
      mostrar_pl == "Si" ? "PL" : nil
    end

    def get_anexo obj, valor
      return (obj.cuenta_custom_attrs['Código Anexo'].presence || search_numero_documento(obj)) unless valor
      afp_method(obj)&.custom_attrs&.dig("Código Anexo").presence || documento(obj)
    end

    def get_cenco obj, valor
      mostrar_ceco = valor ? afp_method(obj)&.custom_attrs&.dig("Mostrar CeCo") : obj.cuenta_custom_attrs['Mostrar CeCo']
      mostrar_ceco == "Si" ? obj.centro_costo : ""
    end

    def documento obj
      obj.numero_documento&.humanize if afp_method(obj)&.custom_attrs&.dig("Agrupador") == "DNI"
    end
end

# EXAMPLE 69
#tcp_consulting.rb


# frozen_string_literal: true

#
#Exportador de comprobante contable para TCP Consulting
class Exportador::Contabilidad::Peru::Personalizadas::TcpConsulting < Exportador::Contabilidad::Peru::CentralizacionContable
  def initialize
    super()
    @extension = 'xlsx'
  end

  CABECERA = [
    'CUENTA',
    'NOMBRE CUENTA',
    'DNI',
    'DEBE',
    'HABER',
    'CECO',
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    grouped = obj_contabilidad.group_by{|l| l.cuenta_custom_attrs&.dig('Proceso') || ''}

    grouped.map do |k, obj|
      libro = generar_cada_libro(empresa, variable, obj)
      ["Libro_#{k}", Exportador::Contabilidad::AccountingFile.new(contents: libro, name_formatter: -> (name) {"#{name} - #{k.presence || 'otros'}"})]
    end.to_h
  end

  def generar_cada_libro(empresa, _variable, obj_contabilidad)
    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    Exportador::BaseXlsx.autofit sheet, [CABECERA]
    Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA, 0)

    agrupador = obj_contabilidad.group_by do |l|
      {
        cuenta: get_cuenta(l, empresa),
        glosa: search_glosa_afp(l),
        dni: search_numero_documento(l),
        deber_o_haber: l.deber_o_haber,
        cencos: search_cc(l),
      }
    end

    data = agrupador.lazy.map do |k, v|
      [
        k[:cuenta],
        k[:glosa],
        k[:dni],
        k[:deber_o_haber] == 'D' ? v.sum(&:monto) : 0,
        k[:deber_o_haber] == 'C' ? v.sum(&:monto) : 0,
        k[:cencos],
      ]
    end
    Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 1, number_format: '###0.00'
    Exportador::BaseXlsx.autofit sheet, [CABECERA]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  private
    def get_cuenta obj, empresa
      return get_cuentas_x_afp(obj, empresa) if obj.cuenta_custom_attrs["AFP"]&.casecmp("si")&.zero?
      obj.cuenta_custom_attrs[empresa.nombre].presence || obj.cuenta_contable
    end

    def get_cuentas_x_afp(obj, empresa)
      afp_method(obj)&.custom_attrs&.dig(empresa.nombre) if ["AFP HABITAT", "AFP INTEGRA", "PRIMA AFP", "PROFUTURO AFP"].include?(obj.afp&.upcase)
    end
end

# EXAMPLE 70
#megacentro.rb


# frozen_string_literal: true

# Clase para generar contabilidad personalizad de Megacentro
class Exportador::Contabilidad::Peru::Personalizadas::Megacentro < Exportador::Contabilidad::Peru::CentralizacionContable
  include HelperContabilidad

  CABECERA = [
    "Imputación Contable",
    "Descripción",
    "Debe Nacional",
    "Haber Nacional",
    "Debe Extranjero",
    "Haber Extranjero",
  ].freeze

  ARR2 = ["Practicante", "Administrativo"].freeze
  ARR = ["LIQUIDACION", "NOMINA"].freeze

  def initialize
    super()
    @extension = 'xlsx'
  end

  def generate_doc(empresa, _variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    hashes = {}
    obj_contabilidad.group_by { |l| l.cuenta_custom_attrs&.dig('Tipo de asiento') || '' }.each do |k, obj|
      libro = generate_centralizacion(empresa, obj, k)
      hashes["Libro_#{k}"] = Exportador::Contabilidad::AccountingFile.new(contents: libro, name_formatter: ->(name) { "#{name} - #{k.presence || 'sin categoría'}" })
    end
    hashes
  end

  def generate_centralizacion(empresa, obj_contabilidad, tipo_asiento)
    return unless obj_contabilidad.present?

    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja(book, "Centralización Contable")
    Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA, 0)

    agrupador = obj_contabilidad.group_by do |l|
      {
        get_cuenta: get_tipo_agrupador(l, tipo_asiento, empresa),
        get_tipo_colaborador: get_tipo_colaborador(l, empresa),
        deber_haber: l.deber_o_haber,
      }
    end

    excel_data = agrupador.lazy.map do |k, v|
      [
        k[:get_cuenta],
        k[:get_tipo_colaborador],
        k[:deber_haber] == "D" ? v.sum(&:monto) : 0,
        k[:deber_haber] == "C" ? v.sum(&:monto) : 0,
        "0",
        "0",
      ]
    end

    Exportador::BaseXlsx.escribir_celdas(sheet, excel_data, offset: 1, number_format: '####0.00')
    Exportador::BaseXlsx.autofit(sheet, [CABECERA])
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  private

    def get_tipo_agrupador(l, tipo_asiento, empresa)
      tipo_agrupacion = empresa.custom_attrs["Agrupacion Asesorias"].to_s
      return get_agrupacion_por_amc(l, tipo_asiento) if tipo_agrupacion.casecmp("si").zero?

      afp = l.cuenta_custom_attrs["AFP"]
      tipo_de_colaborador = l.employee_custom_attrs["Tipo de colaborador"].to_s
      agrupador = l.cuenta_custom_attrs["Agrupador"]

      case agrupador
      when "DNI"
        l.cuenta_contable
      when "CENCO"
        ARR2.include?(tipo_de_colaborador) ? "#{l.centro_costo}#{l.cuenta_contable}" : "#{l.centro_costo}#{l.cuenta_custom_attrs["Cuenta #{tipo_de_colaborador}"]}"
      when "TOTALIZADO"
        return l.cuenta_contable unless afp == "SI"
        search_account(l) if ARR.include?(tipo_asiento)
      end
    end

    def get_agrupacion_por_amc(l, tipo_asiento)
      afp = l.cuenta_custom_attrs["AFP"]
      tipo_de_colaborador = l.employee_custom_attrs["Tipo de colaborador"].to_s
      agrupador = l.cuenta_custom_attrs["Agrupador"]
      tipo_cuenta = tipo_de_colaborador == "Proyecto" ? "PROY" : "OP"

      case agrupador
      when "DNI"
        l.cuenta_contable
      when "CENCO"
        ARR2.include?(tipo_de_colaborador) ? "#{l.centro_costo}#{l.cuenta_custom_attrs["Cuenta ADM Asesoria"]}" : "#{l.centro_costo}#{l.cuenta_custom_attrs["Cuenta #{tipo_cuenta} Asesoria"]}"
      when "TOTALIZADO"
        return l.cuenta_contable unless afp == "SI"
        search_account(l) if ARR.include?(tipo_asiento)
      end
    end

    def get_tipo_colaborador(l, empresa)
      tipo_agrupacion = empresa.custom_attrs["Agrupacion Asesorias"].to_s
      return get_colaborador_por_amc(l) if tipo_agrupacion.casecmp("si").zero?

      tipo_de_colaborador = l.employee_custom_attrs["Tipo de colaborador"]
      afp = l.cuenta_custom_attrs["AFP"]
      return afp_method(l)&.custom_attrs&.dig('Descripcion Concepto') if afp == "SI"
      ARR2.include?(tipo_de_colaborador) ? l.cuenta_custom_attrs["Descripcion Concepto"] : l.cuenta_custom_attrs["Descripcion #{tipo_de_colaborador}"]
    end

    def get_colaborador_por_amc(l)
      tipo_de_colaborador = l.employee_custom_attrs["Tipo de colaborador"]
      afp = l.cuenta_custom_attrs["AFP"]
      tipo_cuenta = tipo_de_colaborador == "Proyecto" ? "PROY" : "OP"
      return afp_method(l)&.custom_attrs&.dig('Descripcion Concepto') if afp == "SI"
      ARR2.include?(tipo_de_colaborador) ? l.cuenta_custom_attrs["Descripcion ADM Asesoria"] : l.cuenta_custom_attrs["Descripcion #{tipo_cuenta} Asesoria"]
    end
end

# EXAMPLE 71
#aelu.rb


# frozen_string_literal: true

# Archivo de Centralizacion Personalizada cliente Aelu
class Exportador::Contabilidad::Peru::Personalizadas::Aelu < Exportador::Contabilidad
  include ContabilidadPeruHelper
  def initialize
    super()
    @extension = 'xlsx'
  end

  HEADER = [
    'NUMERO DE DOCUMENTO',
    'APELLIDOS',
    'NOMBRES',
    'CARGO',
    'CUENTA CONTABLE',
    'VALOR DEBE',
    'VALOR HABER',
    'CENTRO COSTOS',
    'DESCRIPCIÓN CONCEPTO',
  ].freeze

  NO_CONTABILIZAR_INFORMATIVOS = [
    'buk_provision_vacaciones',
    'buk_provision_cts',
    'buk_provision_gratificacion',
    'buk_provision_bonificacion_gratificacion',
    'provision_gratificacion_ajuste_mes_deber',
    'provision_gratificacion_ajuste_mes_haber',
    'provision_bonificacion_extraordinaria_gratificacion_ajuste_mes_deber',
    'provision_bonificacion_extraordinaria_gratificacion_ajuste_mes_haber',
    'provision_cts_ajuste_mes_deber',
    'provision_cts_ajuste_mes_haber',
    'provision_vacaciones_ajuste_mes_deber',
    'provision_vacaciones_ajuste_mes_haber',
  ].freeze

  def generate_doc(empresa, _variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    obj_contabilidad_custom = descartar_informativos(obj_contabilidad)

    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []
    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
    Exportador::BaseXlsx.crear_encabezado(sheet, HEADER, 0)

    agrupador = obj_contabilidad_custom.group_by do |l|
      numero_documento, apellidos, nombres, cargo = data_employee(l)
      {
        numero_doc: numero_documento,
        apellidos: apellidos,
        nombres: nombres,
        cargo: cargo,
        account: plan_contable(l),
        deber_haber: l.deber_o_haber,
        centro_costo: search_cc(l),
        glosa: l.glosa,
      }
    end

    excel_data = agrupador.lazy.map do |k, v|
      [
        k[:numero_doc],
        k[:apellidos],
        k[:nombres],
        k[:cargo],
        k[:account].to_s,
        k[:deber_haber] == "D" ? v.sum(&:monto) : nil,
        k[:deber_haber] == "C" ? v.sum(&:monto) : nil,
        k[:centro_costo],
        k[:glosa],
      ]
    end
    Exportador::BaseXlsx.escribir_celdas sheet, excel_data, offset: 1
    Exportador::BaseXlsx.autofit sheet, [HEADER]
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  private
    def plan_contable l
      l.cuenta_custom_attrs&.dig(l.job_custom_attrs["Grupo"]).presence || l.cuenta_contable
    end

    def data_employee l
      [l.numero_documento.to_s, l.last_name, l.first_name, l.role_name] if l.cuenta_custom_attrs["Agrupador"] == "DNI"
    end

    def descartar_informativos(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_INFORMATIVOS.include?(l.nombre_cuenta) || NO_CONTABILIZAR_INFORMATIVOS.include?(l.item_code)
      end
    end
end

# EXAMPLE 72
#casaidea.rb


# frozen_string_literal: true

#Clase para la centralizacion personalizada Casa Ideas
class Exportador::Contabilidad::Peru::Personalizadas::Casaidea < Exportador::Contabilidad
  include ContabilidadPeruHelper
  require 'csv'
  def initialize
    super()
    @extension = 'csv'
  end
  ASIENTO = {
    "AACC Remuneraciones" => "haberes",
    "AACC Liquidaciones" => "liquidaciones",
    "Provision CTS" => "provcts",
    "Provision Gratificacion" => "provgra",
    "Provision Vacaciones" => "provvac",
    "Sin asiento" => "Sin asiento",
  }.freeze

  SIN_CUENTA = [
    'prestamo en gratificacion',
    'dcto eps hijos mayores 18 años',
    'prestamo',
    'ret. judicial',
    'ret judicial gratificacion',
    'payflow',
    'apoyo a chile',
  ].freeze

  DESCUENTO = [
    'payflow',
    'apoyo a chile',
  ].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    obj_contabilidad_ordenado = obj_contabilidad.group_by{|l| l.cuenta_custom_attrs&.dig("Tipo de asiento") || "Sin asiento"}

    hashes = {}
    obj_contabilidad_ordenado.each do |k, obj|
      concepto = k
      libro = txt_data(obj, variable, empresa, concepto)
      hashes["Libro_#{k}".to_sym] = Exportador::Contabilidad::AccountingFile.new(contents: libro, name_formatter: -> (_name) {"Asiento #{concepto}"})
    end
    hashes
  end

  def txt_data(obj_contabilidad, variable, _empresa, concepto)
    fecha = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
    dia_mes_anio = fecha.strftime("%d.%m.%Y")
    mes = fecha.strftime("%m")
    mes_anio = I18n.l(fecha, format: '%B %Y')

    cabecera = [
      "C",
      "1".rjust(10, " "),
      dia_mes_anio,
      "SA",
      "DHPE",
      dia_mes_anio,
      mes,
      "PEN".rjust(5, " "),
      "1".rjust(9, " "),
      dia_mes_anio,
      glosa_cabecera(concepto, mes_anio),
      glosa_cabecera(concepto, mes_anio),
      "DHPE".ljust(6, " "),
    ]

    agrupado = obj_contabilidad.group_by do |obj|
      {
        clave_contable: get_accounting_key(obj),
        cuenta_contable: get_cuenta_contable(obj),
        newum: newum(obj),
        deber_o_haber: obj.deber_o_haber,
        centro_costo: search_cenco(obj),
        dni: get_numero_documento(obj),
        glosa: obj.cuenta_custom_attrs&.dig("Glosa Detalle"),
      }
    end

    CSV.generate(col_sep: ",") do |csv|
      csv << cabecera
      agrupado.each do |k, v|
        csv << [
          "D",
          "1".rjust(10, " "),
          k[:clave_contable],
          " ".rjust(7, " "),
          k[:cuenta_contable].to_s.rjust(7, " "),
          k[:newum].to_s.ljust(1, " "),
          v.sum(&:monto).to_s.rjust(13, " "),
          " ".rjust(4, " "),
          " ".rjust(10, " "),
          k[:centro_costo].to_s.rjust(10, " "),
          " ".rjust(12, " "),
          dia_mes_anio,
          dia_mes_anio,
          dia_mes_anio,
          " ".rjust(14, " "),
          " ".rjust(12, " "),
          " ".rjust(12, " "),
          " ".rjust(20, " "),
          k[:dni].to_s.rjust(18, " "),
          k[:glosa].to_s.ljust(50, " "),
          " ".rjust(10, " "),
          " ".rjust(2, " "),
          nil,
        ]
      end
    end
  end

  private

    def search_cenco object
      object.cuenta_custom_attrs&.dig("Cenco")&.parameterize == "si" ? object.centro_costo : nil
    end

    def get_cuentas_x_afp(obj)
      case obj.afp&.upcase
      when "AFP HABITAT"
        obj.cuenta_custom_attrs&.dig("AFP HABITAT")
      when "AFP INTEGRA"
        obj.cuenta_custom_attrs&.dig("AFP INTEGRA")
      when "PRIMA AFP"
        obj.cuenta_custom_attrs&.dig("AFP PRIMA")
      when "PROFUTURO AFP"
        obj.cuenta_custom_attrs&.dig("AFP PROFUTURO")
      end
    end

    def get_cuenta_contable obj
      obj.cuenta_custom_attrs&.dig("AFP")&.parameterize == "si" ? get_cuentas_x_afp(obj) : account(obj)
    end

    def account obj
      return if SIN_CUENTA.include?(obj.nombre_cuenta) && !DESCUENTO.include?(obj.nombre_cuenta)
      obj.cuenta_contable
    end


    def newum obj
      obj.nombre_cuenta == 'ret. judicial' ? '2' : nil
    end

    def get_numero_documento obj
      return unless obj.cuenta_custom_attrs&.dig("Agrupador") == "DNI"
      return obj.job_custom_attrs&.dig("DNI Beneficiario") if obj.cuenta_custom_attrs&.dig("DNI Beneficiario")&.parameterize == "si"
      obj.numero_documento&.humanize
    end

    def get_accounting_key obj
      return obj.cuenta_custom_attrs&.dig('Clave contable') if SIN_CUENTA.include?(obj.nombre_cuenta)
      side = obj.deber_o_haber
      case side
      when "D"
        "40"
      when "C"
        "50"
      end
    end

    def glosa_cabecera concepto, mes_anio
      "Plla #{ASIENTO[concepto]}     #{mes_anio}".rjust(26, " ")
    end
end

# EXAMPLE 73
#rla_sav_peru_s_a_c.rb


# rubocop:disable Buk/FileNameClass
# frozen_string_literal: true

#
# clase para generar centralizacion contable personalizada para rla sav peru s a c
class Exportador::Contabilidad::Peru::Personalizadas::RlaSavPeruSAC < Exportador::Contabilidad::Peru::CentralizacionContable
  def initialize
    super()
    @extension = 'xlsx'
  end

  CABECERA = ['CUENTA CONTABLE', 'VALOR DEBE', 'VALOR HABER', 'CENTRO COSTOS', 'DESCRIPCIÓN CONCEPTO'].freeze

  def generate_doc(empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?

    book = Exportador::BaseXlsx.crear_libro
    book.worksheets = []

    obj_contabilidad.group_by{|l| l.cuenta_custom_attrs&.dig('Tipo de Asiento').presence || 'Sin Tipo de Asiento'}.each do |name, obj_conta|
      sheet = Exportador::BaseXlsx.crear_hoja book, name
      crear_encabezados_iniciales(sheet, empresa, variable)
      Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA, 5)

      obj_conta = obj_conta.group_by do |l|
        {
          document_number: l.cuenta_custom_attrs&.dig('Agrupador Centro de Costo') == 'Si' ? nil : l.employee_id,
          cuenta_contable: search_account_cc(l),
          lado: l.deber_o_haber,
          centro_costo: l.centro_costo,
          glosa: l.glosa,
        }
      end

      data = obj_conta.lazy.map do |k, v|
        [
          k[:cuenta_contable],
          k[:lado] == 'D' ? v.sum(&:monto) : nil,
          k[:lado] == 'C' ? v.sum(&:monto) : nil,
          k[:centro_costo],
          k[:glosa],
        ]
      end
      Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 6
    end
    Exportador::BaseXlsx.cerrar_libro(book).contenido
  end

  private

    def crear_encabezados_iniciales(sheet, empresa, variable)
      fecha_generacion = Time.zone.now.strftime("%d/%m/%Y a las %I:%M%p")
      encabezados = [
        ['Libro: Centralización Contable', 0],
        ['Empresa: ' + empresa.nombre + ' (' + empresa.rut.humanize + ')', 1],
        ['Periodo: ' + I18n.l(variable.start_date, format: "%B %Y").capitalize, 2],
        ['Fecha Generación: ' + fecha_generacion, 3],
      ]
      encabezados.each do |encabezado, index|
        Exportador::BaseXlsx.crear_encabezado(sheet, [encabezado], index)
      end
    end
end
# rubocop:enable Buk/FileNameClass

# EXAMPLE 74
#invetsa.rb


# frozen_string_literal: true

#
# Clase para centralizacion de Invetsa
class Exportador::Contabilidad::Peru::Personalizadas::Invetsa < Exportador::Contabilidad
  include ContabilidadPeruHelper

  def initialize
    super()
    @extension = 'xlsx'
  end

  TITULOS = ["ParentKey",
             "LineNum",
             "Line_ID",
             "AccountCode",
             "Debit",
             "Credit",
             "DueDate",
             "ShortName",
             "LineMemo",
             "ReferenceDate1",
             "CostingCode",
             "TaxDate",
             "CostingCode2",
             "CostingCode3",
             "CostingCode4",
             "CostingCode5",].freeze
  ASIENTOS = ["Liquidaciones", "Sueldos", "CTS", "Gratificaciones", "Vacaciones"].freeze
  LIQUIDACIONES = ["Liquidaciones", "Sueldos"].freeze
  NO_CONTABILIZAR_INFORMATIVOS = [
    "provision_bonificacion_extraordinaria_gratificacion_deber",
    "provision_bonificacion_extraordinaria_gratificacion_haber",
    "provision_vacaciones_deber",
    "provision_vacaciones_haber",
    "provision_gratificacion_deber",
    "provision_gratificacion_haber",
    "provision_cts_deber",
    "provision_cts_haber",
  ].freeze

  def generate_doc(_empresa, variable, obj_contabilidad)
    return unless obj_contabilidad.present?
    anio = Variable::Utils.end_of_period(variable.start_date, variable.period_type).strftime('%Y')
    mes = I18n.l(variable.start_date, format: '%B').capitalize
    fecha = Variable::Utils.end_of_period(variable.start_date, variable.period_type).strftime('%Y%m%d')
    mes_anio = I18n.transliterate(I18n.l(Variable::Utils.end_of_period(variable.start_date, variable.period_type), format: "%B %Y"))
    obj_contabilidad = descartar_informativos(obj_contabilidad)
    obj_sin_practicantes = obj_contabilidad.reject{|l| l.employee_custom_attrs&.dig("Tipo de Planilla") == "Practicante"}
    obj_con_practicantes = obj_contabilidad.select{|l| l.employee_custom_attrs&.dig("Tipo de Planilla") == "Practicante"}
    crear_archivo(obj_con_practicantes, obj_sin_practicantes, anio, mes, variable, mes_anio, fecha)
  end
  private
    def crear_archivo obj_con_practicantes, obj_sin_practicantes, anio, mes, variable, mes_anio, fecha
      sueldo = obj_sin_practicantes.select{|l| l.cuenta_custom_attrs&.dig("Proceso") == "Sueldos"}
      sueldo_practicante = obj_con_practicantes.select{|l| l.cuenta_custom_attrs&.dig("Proceso") == "Sueldos"}
      cts = obj_sin_practicantes.select{|l| l.cuenta_custom_attrs&.dig("Proceso") == "CTS"}
      gratificacion = obj_sin_practicantes.select{|l| l.cuenta_custom_attrs&.dig("Proceso") == "Gratificaciones"}
      vacaciones = obj_sin_practicantes.select{|l| l.cuenta_custom_attrs&.dig("Proceso") == "Vacaciones"}
      liquidacion = obj_sin_practicantes.select{|l| l.employee_custom_attrs&.dig("AACC LBS") == "SI" && LIQUIDACIONES.include?(l.cuenta_custom_attrs&.dig("Proceso"))}
      obj_sin_tipo_de_asiento = obj_sin_practicantes.reject do |o|
        ASIENTOS.include?(o.cuenta_custom_attrs&.dig("Proceso"))
      end

      archivos = {
        obj_sueldo: Exportador::Contabilidad::AccountingFile.new(contents: obj_data(sueldo, variable, "Sueldo", mes_anio, fecha), name_formatter: -> (_name) {"Planilla de Sueldos #{mes} #{anio} Empleados" }),
        obj_cts: Exportador::Contabilidad::AccountingFile.new(contents: obj_data(cts, variable, "CTS", mes_anio, fecha), name_formatter: -> (_name) {"Prov. de Cts #{mes} #{anio}" }),
        obj_gratificacion: Exportador::Contabilidad::AccountingFile.new(contents: obj_data(gratificacion, variable, "Gratificaciones", mes_anio, fecha), name_formatter: -> (_name) {"Prov. de Gratificaciones #{mes} #{anio}" }),
        obj_vacaciones: Exportador::Contabilidad::AccountingFile.new(contents: obj_data(vacaciones, variable, "Vacaciones", mes_anio, fecha), name_formatter: -> (_name) {"Prov. de Vacaciones #{mes} #{anio}" }),
        obj_liquidacion: Exportador::Contabilidad::AccountingFile.new(contents: obj_data(liquidacion, variable, "Liquidaciones", mes_anio, fecha), name_formatter: -> (_name) {"Liquidaciones #{mes} #{anio}" }),
        obj_sueldo_practicante: Exportador::Contabilidad::AccountingFile.new(contents: obj_data(sueldo_practicante, variable, "Sueldo", mes_anio, fecha), name_formatter: -> (_name) {"Planilla de Practicantes #{mes} #{anio}" }),
      }

      if obj_sin_tipo_de_asiento.present?
        centralizacion_sin_tipo_de_asiento = obj_data(obj_sin_tipo_de_asiento, variable, "sin_tipo_de_asiento", mes_anio, fecha)
        archivos[:sin_asiento] = Exportador::Contabilidad::AccountingFile.new(contents: centralizacion_sin_tipo_de_asiento, name_formatter: -> (_name) {"Sin tipo de asiento #{mes} #{anio}" })
      end
      archivos
    end

    def obj_data(obj_contabilidad, variable, libro, mes_anio, fecha)
      book = Exportador::BaseXlsx.crear_libro
      book.worksheets = []
      sheet_libro = Exportador::BaseXlsx.crear_hoja book, libro.capitalize
      group = agrupador_centra(obj_contabilidad, variable, libro, mes_anio)
      Exportador::BaseXlsx.escribir_celdas sheet_libro, [TITULOS], offset: 0
      Exportador::BaseXlsx.escribir_celdas sheet_libro, [TITULOS], offset: 1
      data = group.map.with_index(0) do |(k, v), contador|
        print_agrupados(k, v, contador, fecha)
      end
      Exportador::BaseXlsx.escribir_celdas sheet_libro, data, offset: 2, number_format: "###.00"
      Exportador::BaseXlsx.autofit sheet_libro, [TITULOS]
      Exportador::BaseXlsx.cerrar_libro(book).contenido
    end
    def agrupador_centra obj_contabilidad, _variable, libro, mes_anio
      obj_contabilidad.group_by do |obj|
        consting_code_2, consting_code_3, consting_code_4, consting_code_5 = get_consting_codes(obj)
        {
          cuenta_contable: get_cuenta_contable(obj),
          deber_o_haber: obj.deber_o_haber,
          short_name: get_short_name(obj),
          descripcion: get_descripcion(obj, mes_anio, libro),
          centro_costo: show_cenco(obj),
          consting_code_2: consting_code_2,
          consting_code_3: consting_code_3,
          consting_code_4: consting_code_4,
          consting_code_5: consting_code_5,
        }
      end
    end
    def print_agrupados k, v, contador, fecha
      [
        "1",
        contador.to_s,
        contador.to_s,
        k[:cuenta_contable],
        k[:deber_o_haber] == "D" ? v.sum(&:monto) : nil,
        k[:deber_o_haber] == "C" ? v.sum(&:monto) : nil,
        fecha,
        k[:short_name],
        k[:descripcion],
        fecha,
        k[:centro_costo],
        fecha,
        k[:consting_code_2],
        k[:consting_code_3],
        k[:consting_code_4],
        k[:consting_code_5],
      ]
    end
    def get_short_name obj
      case obj.cuenta_custom_attrs&.dig("ShortName")
      when "CUENTA"
        get_cuenta_contable(obj)
      when "NRO DOCUMENTO"
        "P#{obj.numero_documento}"
      else
        obj.cuenta_custom_attrs&.dig("ShortName")
      end
    end

    def get_descripcion obj, mes_anio, libro
      return "Planilla de Practicantes #{mes_anio}" if obj.employee_custom_attrs&.dig("Tipo de Planilla") == "Practicante"
      case libro
      when "Sueldos"
        "Planilla de #{obj.cuenta_custom_attrs&.dig("Proceso")} #{mes_anio} Empleados"
      when "Liquidaciones"
        "Planilla de #{libro} #{mes_anio}"
      else
        "Planilla de #{obj.cuenta_custom_attrs&.dig("Proceso")} #{mes_anio}"
      end
    end

    def get_consting_codes obj
      consting_code_2 = obj.job_custom_attrs&.dig("CostingCode2").presence
      consting_code_3 = obj.job_custom_attrs&.dig("CostingCode3").presence
      consting_code_4 = obj.job_custom_attrs&.dig("CostingCode4").presence
      consting_code_5 = obj.job_custom_attrs&.dig("CostingCode5").presence

      [consting_code_2, consting_code_3, consting_code_4, consting_code_5] unless obj.cuenta_custom_attrs&.dig("Agrupador") == "TOTAL"
    end

    def get_cuentas_x_afp(obj)
      case obj.afp&.upcase
      when "AFP HABITAT"
        obj.cuenta_custom_attrs&.dig("AFP Habitat")
      when "AFP INTEGRA"
        obj.cuenta_custom_attrs&.dig("AFP Integra")
      when "PRIMA AFP"
        obj.cuenta_custom_attrs&.dig("AFP Prima")
      when "PROFUTURO AFP"
        obj.cuenta_custom_attrs&.dig("AFP Profuturo")
      end
    end
    def get_cuenta_contable obj
      obj.nombre_cuenta.include?("afp") ? get_cuentas_x_afp(obj) : obj.cuenta_contable
    end
    def descartar_informativos(obj)
      obj.reject do |l|
        NO_CONTABILIZAR_INFORMATIVOS.include?(l.nombre_cuenta)
      end
    end
end
