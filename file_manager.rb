class FileManager
  require 'fileutils'
  require 'csv'


  Base_folder = '/home/felipe-buker/Documents/clientes'
  def create_folder(folder)
    # binding.pry
    new_folder = File.join(Base_folder, folder)
    Dir.mkdir(new_folder) unless File.directory?(new_folder)
  
    csv_new_file = 'detalle.csv'
    csv_file = File.join(new_folder, csv_new_file)

    # return unless File.file?(csv_file)

    CSV.open(csv_file, 'w') do |csv|

      puts 'File Created'
    end
    puts "done!"

  end

  def create_centra_file(name, country)

  end

end