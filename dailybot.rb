#!/usr/bin/env ruby
class Dailybot
  require 'rubygems'
  require 'dotenv/load'
  require 'rest-client'
  require 'json'
  require 'pry'
  require 'colorize'
  require_relative 'helper'
  include Helper

  $LOAD_PATH << File.join(__dir__, '.')

  autoload :FreshdeskConnection, 'freshdesk_connection'
  autoload :ChatgptConnection, 'chatgpt_connection'
  autoload :FileManager, 'file_manager'

  def looking_what_is_new
    fresh = FreshdeskConnection.new(ENV["FRESH_API_KEY"])
    tickets = fresh.get_tickets

    gpt = ChatgptConnection.new(ENV["CHATGPT_API_KEY"])
    tickets_summarized = gpt.get_tickets_summary(tickets)
    tickets_summarized.each do |ticket, v|
      # puts ticket
    end


    # crear carpeta cliente
    file_manager = FileManager.new()

    tickets_summarized.each do |ticket|

      summary = ticket['summary']
      subdomain = ticket['company'] # url.match(/^http[s]?:\/\/([a-zA-Z0-9-]+)\./)&.captures&.first

      # url_company = ticket[custom_url_empresa] || description.regex(\http...buk.[cl|pe|br|co|mx]..\)
      # folder_name = url_company.tr('https://', '').tr('.buk*', '')

      ticket_id = ticket['id']

      puts "#{ticket_id}".colorize(:yellow) + "#{subdomain}" + "#{summary}"

      # *pendiente
      # connect to drive to download files
      # files = DriveConnection.new().download_files(ticket)

      # puts "#{k}:".colorize(:yellow) + " #{v}".colorize(get_color(v))

      
      # seleccionar template (template, extension, pais, nombre_contabilidad)
      # generar data en generate_doc
      # 
    end
    
    puts "do you want to work in a ticket?"
    puts "enter the ticket id if you want"
    puts "ctrl+c or exit"
    ticket_selected = gets.chomp
    if ['exit', 'n', 'no', nil, '', ' '].include?(ticket_selected.downcase)
      puts 'bye'
      exit
    end



    ticket = tickets_summarized.select{|t| t['id'] == ticket_selected.to_i}.first
    exit if ticket.nil?
    folder_name = "#{ticket['id']} #{ticket['company']}"
    folder = file_manager.create_folder(folder_name)
    puts "folder created => #{folder}"
    puts "download the requeriment file and put that in the ticket's folder"

    ticket_attached_file = ticket['attached_file']

    puts "descargar archivo de levantamiento " + "\e]8;;#{ticket_attached_file}\aAQUÍ\e]8;;\a"

    waiting = gets
    data_from_xlsx = file_manager.read_xlsx_file
    csv_path = file_manager.create_csv_file(data_from_xlsx, ticket['company'], ticket['country'])

    json_data = gpt.generate_json_data(csv_path)
  end
end
