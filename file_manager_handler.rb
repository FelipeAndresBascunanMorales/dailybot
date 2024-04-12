class FileManagerHandler < AbstractHandler
  require 'fileutils'
  require 'csv'
  require 'roo'

  def initialize
    @Base_folder = '/home/felipe-buker/Documents/clientes'
  end

  @@json_folder = '/home/felipe-buker/CosasDev/dailybot/examples/json_responses'

  COUNTRIES = {
    'CO' => 'Colombia',
    'CL' => 'Chile',
    'MX' => 'Mexico',
    'PE' => 'Peru',
    'BR' => 'Brasil',
  }
  
  MSJ_DESCARGA = 'descargar archivo de levantamiento'
  MSJ_FOLDER = "descarga el archivo xlsx con el requerimiento en la siguiente ruta"
  
  def handle(request)
    key, value = request.to_a.flatten
    case key
    when :ticket_to_work
      create_folder(value[:folder_name])
      ConsoleHandler.print_link(value[:ticket]['attached_file'], 'AQUÍ', MSJ_DESCARGA)
      read_xlsx_file
      csv = create_csv_file(value[:ticket]['company'], value[:ticket]['country'])
      
      super({to_jsonify: csv})
    when :write_to_buk
      create_centra_file(value[:data], value[:country], value[:company])
    end
  end

  def create_folder(folder)
    @new_folder = File.join(@Base_folder, folder)
    Dir.mkdir(@new_folder) unless File.directory?(@new_folder)
  
    csv_new_file = 'detalle.csv'
    csv_file = File.join(@new_folder, csv_new_file)

    # return unless File.file?(csv_file)

    CSV.open(csv_file, 'w') do |csv|

        csv << ['resumen']
        csv << [nil]
        csv << ['agrupado', 'pais', 'formato', 'archivos_separados', 'nombre_atributo_separador',]
        csv << ['si', 'chile', 'xlsx', 'no', '',]
        csv << [nil]
        csv << ['detalle']

      puts 'File Created'
    end
    @new_folder
  end


  def read_xlsx_file
    files_in_folder = Dir.entries(@new_folder)
    xlsx_file = files_in_folder.select { |file| File.extname(file) == '.xlsx' }.first

    while xlsx_file.nil?
      ConsoleHandler.print_folder(@new_folder, MSJ_FOLDER)
      files_in_folder = Dir.entries(@new_folder)
      xlsx_file = files_in_folder.select { |file| File.extname(file) == '.xlsx' }.first
    end

    xlsx_file_path = File.join(@new_folder, xlsx_file)
    begin
      requeriment_file = Roo::Spreadsheet.open(xlsx_file_path)
    rescue SystemCallError => e
      puts "no existe la carpeta del ticket"
    end
    initial_data = []
    requeriment_file.sheet(1).each do |r|
      initial_data <<  r
    end
    
    detailed_data = []
    requeriment_file.sheet(2).each do |r|
      detailed_data <<  r
    end
    initial_data = clean_initial_data(initial_data[2..22])
    detailed_data = clean_detailed_data(detailed_data)
    
    @initial_data = initial_data.transpose
    @detailed_data = detailed_data.transpose
    nil
  end

  def create_csv_file(company, country)
    csv_new_file = 'detalle.csv'
    csv_file = File.join(@new_folder, csv_new_file)

    @initial_data[0].insert(0, 'company')
    @initial_data[1].insert(0, company)

    @initial_data[0].insert(0, 'country')
    @initial_data[1].insert(0, country)

    CSV.open(csv_file, 'w') do |csv|

        csv << ['resumen']
        csv << [nil]
        @initial_data.each{|r| csv << r}
        csv << [nil]
        csv << [nil]
        csv << ['detalle']
        csv << [nil]
        @detailed_data.each{|r| csv << r}
      puts 'File Created'
    end
    csv_file
  end

  def clean_detailed_data(data)
    start_in = nil

    data.each.with_index do |d, index|
      if d.include?("Detalle de centralización: Cuerpo")
        start_in = index
        break
      end
    end

    if !start_in.nil? # tomamos sólo la data detalle
      data[start_in..(start_in + 8)]
    elsif "mejor_que_no"
      # mmm no me da confianza, podría borrar data y desplazar todo, pero hay que probar
      ChatgptHandler.clean_data(data.transpose, ENV["CHATGPT_API_KEY"])
    else # tomamos todo lo que pueda ser útil
      data.delete_if {|row| row[1..-1].all?(&:nil?)}
      data.transpose.delete_if{|column| column[1..-1].all?(&:nil?)}.transpose
    end
  end

  def clean_initial_data(data)
    # data = ChatgptHandler.clean_data(data.transpose, ENV["CHATGPT_API_KEY"])
    # if !data.nil?
    #   data
    # else # tomamos todo lo que pueda ser útil
    #   data.delete_if {|row| row[1..-1].all?(&:nil?)}
    #   data.transpose.delete_if{|column| column[1..-1].all?(&:nil?)}.transpose
    # end
    data.delete_if {|row| row[1..-1].all?(&:nil?)}
    data.transpose.delete_if{|column| column[1..-1].all?(&:nil?)}.transpose
  end
  

  def create_centra_file(data, country, name)
    puts "#{country} #{name}"
    paths = {
      'PE' => ENV["PATH_CENTRAS_PERU"],
      'CL' => ENV["PATH_CENTRAS_CHILE"],
      'CO' => ENV["PATH_CENTRAS_COLOMBIA"],
      'MX' => ENV["PATH_CENTRAS_MEXICO"],
    }

    path = paths[country] || ENV["PATH_CENTRAS_CHILE"]
    name = name || 'centra_ejemplo'
    timestamp = Time.now.to_i
    File.open("#{@@json_folder}/#{name}#{timestamp}.rb", 'w') do |file|
      file.write(data)
    end

    timestamp = Time.now.to_i
    file_path = "#{path}/#{name}.rb"

    if replace_file?(file_path)
      File.open(file_path, 'w') do |file|
        file.write(data)
      end
    else
      puts "File replacement cancelled."
    end
    puts "tamos listo!"
  end

  def replace_file?(file_path)
    if File.exist?(file_path)
      puts "A file already exists at #{file_path}. Do you want to replace it with the new data? (yes/no)"
      user_input = gets.chomp.downcase
      return user_input == 'yes'
    else
      return true # If the file doesn't exist, proceed with replacement
    end
  end

  def self.save_json_file(data)
    file_name = data["compania"] || 'sin_nombre'
    timestamp = Time.now.to_i
    File.open("#{@@json_folder}/#{file_name}#{timestamp}.json", 'w') do |file|
      file.write(JSON.generate(data))
    end
  end

  def self.get_template(data)
    # format, country, grouped_data, separated_in_files = false, separated_in_sheets = false, headers = true
    
    key = {
      format: data['format'],
      # country: data['country'],
      grouped_data: data['grouped_data'] || false,
      separated_in_files: data['separated_in_files'] || false,
      separated_in_sheets: data['separated_in_sheets'] || false,
    }

    binding.pry if TEMPLATES[key].nil?
    p key
    TEMPLATES[key]&.call(COUNTRIES[data['country'].upcase], data['company_name'])
  end

  TEMPLATES = {
    {
      format: 'xlsx',
      grouped_data: true,
      separated_in_files: false,
      separated_in_sheets: false,
    } => -> (country, company) {
    """
            # frozen_string_literal: true
            
            #
            # clase para generar centralizacion contable personalizada para #{company}
            class Exportador::Contabilidad::#{country}::Personalizadas::#{company.capitalize} < Exportador::Contabilidad::#{country}::CentralizacionContable
              def initialize
                super()
                @extension = 'xlsx'
              end
            
              CABECERA = [
                # COMPLETE HERE WITH CABECERA
              ].freeze
            
              def generate_doc(empresa, variable, obj_contabilidad)
                return unless obj_contabilidad.present?
            
                book = Exportador::BaseXlsx.crear_libro
                book.worksheets = []
                sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
                Exportador::BaseXlsx.autofit sheet, [CABECERA]
                Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA, 0)
            
                date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
                date_ddmmyyyy = I18n.l(date, format: '%d-%m-%Y')

                # COMPLETE HERE WITH DATA FROM EMPRESA OR VARIABLE TO BE USED IN THE ARRAY TO BE PRINTED
            
                data = obj_contabilidad.lazy.map do |l|
                  [
                    # COMPLETE HERE WITH DATA TO BE PRINTED
                  ]
                end

                Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 1, number_format: '#,##0'
                Exportador::BaseXlsx.cerrar_libro(book).contenido
              end

              # COMPLETE HERE IF IS NECESARY TO CREATE A METHOD TO RETRIEVE DATA
            end
           
          """
    },
    {
      format: 'xlsx',
      grouped_data: false,
      separated_in_files: nil,
      separated_in_sheets: nil,
    } =>  -> (country, company) {
      """
        # frozen_string_literal: true
        
        #
        # clase para generar centralizacion contable personalizada para #{company}
        class Exportador::Contabilidad::#{country}::Personalizadas::#{company.capitalize} < Exportador::Contabilidad::#{country}::CentralizacionContable
          def initialize
            super()
            @extension = 'xlsx'
          end
        
          CABECERA = [
            # COMPLETE HERE WITH CABECERA
          ].freeze
        
          def generate_doc(empresa, variable, obj_contabilidad)
            return unless obj_contabilidad.present?
        
            book = Exportador::BaseXlsx.crear_libro
            book.worksheets = []
            sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre
            Exportador::BaseXlsx.autofit sheet, [CABECERA]
            Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA, 0)
        
            date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)
            date_ddmmyyyy = date.strftime('%d-%m-%Y')
        
            # COMPLETE HERE WITH DATA FROM EMPRESA OR VARIABLE TO BE USED IN THE ARRAY TO BE PRINTED

            data = obj_contabilidad.lazy.map do |l|
              [
                
                # COMPLETE HERE WITH DATA TO BE PRINTED

              ]
            end
        
            Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 1, number_format: '#,##0'
            Exportador::BaseXlsx.cerrar_libro(book).contenido
          end
        end
      """
    },
    {
      format: 'txt',
      grouped_data: false,
      separated_in_files: false,
      separated_in_sheets: false,
    } => -> (country, company) {
      """
        # frozen_string_literal: true

        #
        # clase para generar centralizacion contable personalizada para #{company}
        class Exportador::Contabilidad::#{country}::Personalizadas::#{company.capitalize} < Exportador::Contabilidad::#{country}::CentralizacionContable
          require 'csv'
          def initialize
            super()
            @extension = 'txt'
          end

          CABECERA =
            [
              # COMPLETE HERE WITH CABECERA
            ].freeze

          def generate_doc(empresa, variable, obj_contabilidad)
            return unless obj_contabilidad.present?

            # COMPLETE HERE VARIABLES
            # THIS MUST BE DATA FROM EMPRESA OR VARIABLE TO BE USED IN THE ARRAY TO BE PRINTED
            # date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)

            CSV.generate(col_sep: ';') do |csv|
              csv << CABECERA
              obj_contabilidad.each do |l|
                csv << [

                  # COMPLETE HERE WITH DATA TO BE PRINTED

                ]
              end
            end
          end
        end

        # COMPLETE HERE METHODS
      """
    },
    {
      format: 'txt',
      grouped_data: true,
      separated_in_files: false,
      separated_in_sheets: false,
    } => -> (country, company) {
      """
        # frozen_string_literal: true

        #
        # clase para generar centralizacion contable personalizada para #{company}
        class Exportador::Contabilidad::#{country}::Personalizadas::#{company.capitalize} < Exportador::Contabilidad::#{country}::CentralizacionContable
          require 'csv'
          def initialize
            super()
            @extension = 'txt'
          end

          CABECERA =
            [
              # COMPLETE HERE WITH CABECERA
            ].freeze

          def generate_doc(empresa, variable, obj_contabilidad)
            return unless obj_contabilidad.present?

            # COMPLETE HERE VARIABLES
            # THIS MUST BE DATA FROM EMPRESA OR VARIABLE TO BE USED IN THE ARRAY TO BE PRINTED
            # date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)

            obj_contabilidad = obj_contabilidad.group_by do |l|
              {
        
                # COMPLETE HERE GROUP_BY

                # EXAMPLES:
                # cuenta_contable: l.cuenta_contable,
                # lado: l.deber_o_haber,
                # centro_costos: l.centro_costo,
                # glosa: l.glosa,
              }
            end
        

            CSV.generate(col_sep: ';') do |csv|
              csv << CABECERA
              obj_contabilidad.each do |k, v|
                csv << [

                # COMPLETE HERE DATA TO BE PRINTED
              
                # EXAMPLES
                # date_ddmmyyyy,
                # k[:nombre],
                # k[:cuenta_contable],
                # k[:lado] == 'C' ? v.sum(&:monto) : nil,
                # k[:lado] == 'D' ? v.sum(&:monto) : nil,
                # k[:centro_costos],
                # k[:glosa],
                ]
              end
            end
          end
        end
      """
    },
    {
      format: 'txt',
      grouped_data: false,
      separated_in_files: nil,
      separated_in_sheets: nil,
    } => -> (country, company) {
      """
        # frozen_string_literal: true

        #
        # clase para generar centralizacion contable personalizada para #{company}
        class Exportador::Contabilidad::#{country}::Personalizadas::#{company.capitalize} < Exportador::Contabilidad::#{country}::CentralizacionContable
          require 'csv'
          def initialize
            super()
            @extension = 'txt'
          end

          CABECERA =
            [
              # COMPLETE HERE WITH CABECERA
            ].freeze

          def generate_doc(empresa, variable, obj_contabilidad)
            return unless obj_contabilidad.present?

            # COMPLETE HERE VARIABLES
            # THIS MUST BE DATA FROM EMPRESA OR VARIABLE TO BE USED IN THE ARRAY TO BE PRINTED
            # date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)

            CSV.generate(col_sep: ';') do |csv|
              csv << CABECERA
              obj_contabilidad.each do |l|
                csv << [

                  # COMPLETE HERE WITH DATA TO BE PRINTED

                ]
              end
            end
          end
        end

        # COMPLETE HERE METHODS
      """
    },
    {
      format: 'txt',
      grouped_data: true,
      separated_in_files: nil,
      separated_in_sheets: nil,
    } => -> (country, company) {
      """
        # frozen_string_literal: true

        #
        # clase para generar centralizacion contable personalizada para #{company}
        class Exportador::Contabilidad::#{country}::Personalizadas::#{company.capitalize} < Exportador::Contabilidad::#{country}::CentralizacionContable
          require 'csv'
          def initialize
            super()
            @extension = 'txt'
          end

          CABECERA =
            [
              # COMPLETE HERE WITH CABECERA
            ].freeze

          def generate_doc(empresa, variable, obj_contabilidad)
            return unless obj_contabilidad.present?

            # COMPLETE HERE VARIABLES
            # THIS MUST BE DATA FROM EMPRESA OR VARIABLE TO BE USED IN THE ARRAY TO BE PRINTED
            # date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)

            obj_contabilidad = obj_contabilidad.group_by do |l|
              {
        
                # COMPLETE HERE GROUP_BY

                # EXAMPLES:
                # cuenta_contable: l.cuenta_contable,
                # lado: l.deber_o_haber,
                # centro_costos: l.centro_costo,
                # glosa: l.glosa,
              }
            end
        

            CSV.generate(col_sep: ';') do |csv|
              csv << CABECERA
              obj_contabilidad.each do |k, v|
                csv << [

                # COMPLETE HERE DATA TO BE PRINTED
              
                # EXAMPLES
                # date_ddmmyyyy,
                # k[:nombre],
                # k[:cuenta_contable],
                # k[:lado] == 'C' ? v.sum(&:monto) : nil,
                # k[:lado] == 'D' ? v.sum(&:monto) : nil,
                # k[:centro_costos],
                # k[:glosa],
                ]
              end
            end
          end
        end
      """
    },
    {
      format: 'txt',
      grouped_data: nil,
      separated_in_files: nil,
      separated_in_sheets: nil,
    } => -> (country, company) {
      """
        # frozen_string_literal: true

        #
        # clase para generar centralizacion contable personalizada para #{company}
        class Exportador::Contabilidad::#{country}::Personalizadas::#{company.capitalize} < Exportador::Contabilidad::#{country}::CentralizacionContable
          require 'csv'
          def initialize
            super()
            @extension = 'txt'
          end

          CABECERA =
            [
              # COMPLETE HERE WITH CABECERA
            ].freeze

          def generate_doc(empresa, variable, obj_contabilidad)
            return unless obj_contabilidad.present?

            # COMPLETE HERE VARIABLES
            # THIS MUST BE DATA FROM EMPRESA OR VARIABLE TO BE USED IN THE ARRAY TO BE PRINTED
            # date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)

            CSV.generate(col_sep: ';') do |csv|
              csv << CABECERA
              obj_contabilidad.each do |l|
                csv << [

                  # COMPLETE HERE WITH DATA TO BE PRINTED

                ]
              end
            end
          end
        end

        # COMPLETE HERE METHODS
      """
    },
    {
      format: 'csv',
      grouped_data: false,
      separated_in_files: false,
      separated_in_sheets: false,
    } => -> (country, company) {
      """
        # frozen_string_literal: true

        #
        # clase para generar centralizacion contable personalizada para #{company}
        class Exportador::Contabilidad::#{country}::Personalizadas::#{company.capitalize} < Exportador::Contabilidad::#{country}::CentralizacionContable
          require 'csv'
          def initialize
            super()
            @extension = 'csv'
          end

          CABECERA =
            [
              # COMPLETE HERE WITH CABECERA
            ].freeze

          def generate_doc(empresa, variable, obj_contabilidad)
            return unless obj_contabilidad.present?

            # COMPLETE HERE VARIABLES
            # THIS MUST BE DATA FROM EMPRESA OR VARIABLE TO BE USED IN THE ARRAY TO BE PRINTED
            # date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)

            CSV.generate(col_sep: ';') do |csv|
              csv << CABECERA
              obj_contabilidad.each do |l|
                csv << [

                  # COMPLETE HERE WITH DATA TO BE PRINTED

                ]
              end
            end
          end
        end

        # COMPLETE HERE METHODS
      """
    },
    {
      format: 'csv',
      grouped_data: true,
      separated_in_files: false,
      separated_in_sheets: false,
    } => -> (country, company) {
      """
        # frozen_string_literal: true

        #
        # clase para generar centralizacion contable personalizada para #{company}
        class Exportador::Contabilidad::#{country}::Personalizadas::#{company.capitalize} < Exportador::Contabilidad::#{country}::CentralizacionContable
          require 'csv'
          def initialize
            super()
            @extension = 'csv'
          end

          CABECERA =
            [
              # COMPLETE HERE WITH CABECERA
            ].freeze

          def generate_doc(empresa, variable, obj_contabilidad)
            return unless obj_contabilidad.present?

            # COMPLETE HERE VARIABLES
            # THIS MUST BE DATA FROM EMPRESA OR VARIABLE TO BE USED IN THE ARRAY TO BE PRINTED
            # date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)

            obj_contabilidad = obj_contabilidad.group_by do |l|
              {
        
                # COMPLETE HERE GROUP_BY

                # EXAMPLES:
                # cuenta_contable: l.cuenta_contable,
                # lado: l.deber_o_haber,
                # centro_costos: l.centro_costo,
                # glosa: l.glosa,
              }
            end
        

            CSV.generate(col_sep: ';') do |csv|
              csv << CABECERA
              obj_contabilidad.each do |k, v|
                csv << [

                # COMPLETE HERE DATA TO BE PRINTED
              
                # EXAMPLES
                # date_ddmmyyyy,
                # k[:nombre],
                # k[:cuenta_contable],
                # k[:lado] == 'C' ? v.sum(&:monto) : nil,
                # k[:lado] == 'D' ? v.sum(&:monto) : nil,
                # k[:centro_costos],
                # k[:glosa],
                ]
              end
            end
          end
        end
      """
    },
    {
      format: 'csv',
      grouped_data: false,
      separated_in_files: nil,
      separated_in_sheets: nil,
    } => -> (country, company) {
      """
        # frozen_string_literal: true

        #
        # clase para generar centralizacion contable personalizada para #{company}
        class Exportador::Contabilidad::#{country}::Personalizadas::#{company.capitalize} < Exportador::Contabilidad::#{country}::CentralizacionContable
          require 'csv'
          def initialize
            super()
            @extension = 'csv'
          end

          CABECERA =
            [
              # COMPLETE HERE WITH CABECERA
            ].freeze

          def generate_doc(empresa, variable, obj_contabilidad)
            return unless obj_contabilidad.present?

            # COMPLETE HERE VARIABLES
            # THIS MUST BE DATA FROM EMPRESA OR VARIABLE TO BE USED IN THE ARRAY TO BE PRINTED
            # date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)

            CSV.generate(col_sep: ';') do |csv|
              csv << CABECERA
              obj_contabilidad.each do |l|
                csv << [

                  # COMPLETE HERE WITH DATA TO BE PRINTED

                ]
              end
            end
          end
        end

        # COMPLETE HERE METHODS
      """
    },
    {
      format: 'csv',
      grouped_data: true,
      separated_in_files: nil,
      separated_in_sheets: nil,
    } => -> (country, company) {
      """
        # frozen_string_literal: true

        #
        # clase para generar centralizacion contable personalizada para #{company}
        class Exportador::Contabilidad::#{country}::Personalizadas::#{company.capitalize} < Exportador::Contabilidad::#{country}::CentralizacionContable
          require 'csv'
          def initialize
            super()
            @extension = 'csv'
          end

          CABECERA =
            [
              # COMPLETE HERE WITH CABECERA
            ].freeze

          def generate_doc(empresa, variable, obj_contabilidad)
            return unless obj_contabilidad.present?

            # COMPLETE HERE VARIABLES
            # THIS MUST BE DATA FROM EMPRESA OR VARIABLE TO BE USED IN THE ARRAY TO BE PRINTED
            # date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)

            obj_contabilidad = obj_contabilidad.group_by do |l|
              {
        
                # COMPLETE HERE GROUP_BY

                # EXAMPLES:
                # cuenta_contable: l.cuenta_contable,
                # lado: l.deber_o_haber,
                # centro_costos: l.centro_costo,
                # glosa: l.glosa,
              }
            end
        

            CSV.generate(col_sep: ';') do |csv|
              csv << CABECERA
              obj_contabilidad.each do |k, v|
                csv << [

                # COMPLETE HERE DATA TO BE PRINTED
              
                # EXAMPLES
                # date_ddmmyyyy,
                # k[:nombre],
                # k[:cuenta_contable],
                # k[:lado] == 'C' ? v.sum(&:monto) : nil,
                # k[:lado] == 'D' ? v.sum(&:monto) : nil,
                # k[:centro_costos],
                # k[:glosa],
                ]
              end
            end
          end
        end
      """
    },
    {
      format: 'csv',
      grouped_data: nil,
      separated_in_files: nil,
      separated_in_sheets: nil,
    } => -> (country, company) {
      """
        # frozen_string_literal: true

        #
        # clase para generar centralizacion contable personalizada para #{company}
        class Exportador::Contabilidad::#{country}::Personalizadas::#{company.capitalize} < Exportador::Contabilidad::#{country}::CentralizacionContable
          require 'csv'
          def initialize
            super()
            @extension = 'csv'
          end

          CABECERA =
            [
              # COMPLETE HERE WITH CABECERA
            ].freeze

          def generate_doc(empresa, variable, obj_contabilidad)
            return unless obj_contabilidad.present?

            # COMPLETE HERE VARIABLES
            # THIS MUST BE DATA FROM EMPRESA OR VARIABLE TO BE USED IN THE ARRAY TO BE PRINTED
            # date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)

            CSV.generate(col_sep: ';') do |csv|
              csv << CABECERA
              obj_contabilidad.each do |l|
                csv << [

                  # COMPLETE HERE WITH DATA TO BE PRINTED

                ]
              end
            end
          end
        end

        # COMPLETE HERE METHODS
      """
    }
  }

end