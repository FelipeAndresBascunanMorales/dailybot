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
      puts ticket
    end


    # crear carpeta cliente
    file_manager = FileManager.new()

    tickets_summarized.each do |ticket|

      description = ticket['summary']
      subdomain = ticket['company']# url.match(/^http[s]?:\/\/([a-zA-Z0-9-]+)\./)&.captures&.first

      # url_company = ticket[custom_url_empresa] || description.regex(\http...buk.[cl|pe|br|co|mx]..\)
      # folder_name = url_company.tr('https://', '').tr('.buk*', '')

      ticket_id = ticket['id']

      puts "#{ticket_id} #{subdomain} #{description}"
      # *pendiente
      # connect to drive to download files
      # files = DriveConnection.new().download_files(ticket)

      
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
    file_manager.create_folder(folder_name)

  end
end
