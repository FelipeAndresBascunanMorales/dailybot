class FileManager
  require 'fileutils'
  require 'csv'
  require 'roo'

  def initialize()
    @Base_folder = '/home/felipe-buker/Documents/clientes'
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
      puts "descarga el archivo xlsx del requerimiento en la carpeta del ticket"
      puts "#{@new_folder}/"
      gets
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
    
    initial_data = initial_data[2..22].transpose
    detailed_data = detailed_data.transpose

    [initial_data, detailed_data]
    # innecesario
    # 

    # largest_row = detailed_data.map{|r| r.reverse.drop_while(&:nil?).reverse.count}.max
    # detailed_data.each do |r|
    #   if r.count == largest_row

    #   end
    # end

  end

  def create_csv_file(resumen_detalle, company, country)
    csv_new_file = 'detalle.csv'
    csv_file = File.join(@new_folder, csv_new_file)

    resumen = resumen_detalle.first
    detalle = resumen_detalle.last

    resumen[0].insert(0, 'company')
    resumen[1].insert(0, company)

    resumen[0].insert(0, 'country')
    resumen[1].insert(0, country)

    CSV.open(csv_file, 'w') do |csv|

        csv << ['resumen']
        csv << [nil]
        resumen.each{|r| csv << r}
        csv << [nil]
        csv << [nil]
        csv << ['detalle']
        csv << [nil]
        detalle.each{|r| csv << r}
      puts 'File Created'
    end
    csv_file
  end
  

  def create_centra_file(name, country)
  end

end