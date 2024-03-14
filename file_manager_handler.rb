class FileManagerHandler < AbstractHandler
  require 'fileutils'
  require 'csv'
  require 'roo'

  def initialize
    @Base_folder = '/home/felipe-buker/Documents/clientes'
  end
  
  MSJ_DESCARGA = 'descargar archivo de levantamiento'
  MSJ_FOLDER = "descarga el archivo xlsx con el requerimiento en la siguiente ruta"
  
  def handle(request)
    key, value = request.to_a.flatten
    case key
    when :ticket_to_work
      create_folder(value[:folder_name])
      binding.pry
      ConsoleHandler.print_link(value[:ticket]['attached_file'], 'AQUÍ', MSJ_DESCARGA)
      read_xlsx_file
      csv = create_csv_file(value[:ticket]['company'], value[:ticket]['country'])
      
      super({to_jsonify: csv})
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
    
    @initial_data = initial_data[2..22].transpose
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
  

  def create_centra_file(name, country)
  end

  def self.get_template(data)
    # format, country, grouped_data, separated_in_files = false, separated_in_sheets = false, headers = true
    
    key = {
      format: data['format'],
      # country: data['country'],
      grouped_data: data['grouped_data'],
      separated_in_files: data['separated_in_files'],
      separated_in_sheets: data['separated_in_sheets'],
    }

    TEMPLATES[key]
  end

  TEMPLATES = {
    {
      format: 'xlsx',
      grouped_data: true,
      separated_in_files: false,
      separated_in_sheets: false,
    } => [
            "# frozen_string_literal: true",
            "",
            "#",
            "# clase para generar centralizacion contable personalizada para ${TM_FILENAME_BASE/[\\_]+/ /g}",
            "class Exportador::Contabilidad::${2|Chile,Colombia,Peru,Mexico|}::Personalizadas::${TM_FILENAME_BASE/(.*)/${1:/pascalcase}/} < Exportador::Contabilidad::${2}::CentralizacionContable",
            "  def initialize",
            "    super()",
            "    @extension = 'xlsx'",
            "  end",
            "",
            "  CABECERA = [",
            "    ${0:'cabecera',}",
            "  ].freeze",
            "",
            "  def generate_doc(empresa, variable, obj_contabilidad)",
            "    return unless obj_contabilidad.present?",
            "",
            "    book = Exportador::BaseXlsx.crear_libro",
            "    book.worksheets = []",
            "    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre",
            "    Exportador::BaseXlsx.autofit sheet, [CABECERA]",
            "    Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA, 0)",
            "",
            "    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)",
            "    date_ddmmyyyy = date.strftime('%d-%m-%Y')",
            "",
            "    data = obj_contabilidad.lazy.map do |l|",
            "      [",
            "        ",
            "",
            "        date_ddmmyyyy,",
            "        l.cuenta_contable,",
            "        l.glosa,",
            "        l.deber,",
            "        l.haber,",
            "      ]",
            "    end",
            "",
            "    Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 1, number_format: '#,##0'",
            "    Exportador::BaseXlsx.cerrar_libro(book).contenido",
            "  end",
            "end",
            "",
          ],
          {
            format: 'xlsx',
            grouped_data: nil,
            separated_in_files: nil,
            separated_in_sheets: nil,
          } => [
                  "# frozen_string_literal: true",
                  "",
                  "#",
                  "# clase para generar centralizacion contable personalizada para ${TM_FILENAME_BASE/[\\_]+/ /g}",
                  "class Exportador::Contabilidad::${2|Chile,Colombia,Peru,Mexico|}::Personalizadas::${TM_FILENAME_BASE/(.*)/${1:/pascalcase}/} < Exportador::Contabilidad::${2}::CentralizacionContable",
                  "  def initialize",
                  "    super()",
                  "    @extension = 'xlsx'",
                  "  end",
                  "",
                  "  CABECERA = [",
                  "    ${0:'cabecera',}",
                  "  ].freeze",
                  "",
                  "  def generate_doc(empresa, variable, obj_contabilidad)",
                  "    return unless obj_contabilidad.present?",
                  "",
                  "    book = Exportador::BaseXlsx.crear_libro",
                  "    book.worksheets = []",
                  "    sheet = Exportador::BaseXlsx.crear_hoja book, empresa.nombre",
                  "    Exportador::BaseXlsx.autofit sheet, [CABECERA]",
                  "    Exportador::BaseXlsx.crear_encabezado(sheet, CABECERA, 0)",
                  "",
                  "    date = Variable::Utils.end_of_period(variable.start_date, variable.period_type)",
                  "    date_ddmmyyyy = date.strftime('%d-%m-%Y')",
                  "",
                  "    data = obj_contabilidad.lazy.map do |l|",
                  "      [",
                  "        ",
                  "",
                  "        date_ddmmyyyy,",
                  "        l.cuenta_contable,",
                  "        l.glosa,",
                  "        l.deber,",
                  "        l.haber,",
                  "      ]",
                  "    end",
                  "",
                  "    Exportador::BaseXlsx.escribir_celdas sheet, data, offset: 1, number_format: '#,##0'",
                  "    Exportador::BaseXlsx.cerrar_libro(book).contenido",
                  "  end",
                  "end",
                  "",
                ]
  }

end