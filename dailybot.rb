#!/usr/bin/env ruby

# The Handler interface
class Handler
  def next_handler=(handler)
    raise NotImplementedError, "#{self.class} has no implemented method #{__method__}"
  end

  def handle(request)
    raise NotImplementedError, "#{self.class} has no implemented method #{__method__}"
  end
end

# the base abstract handler
class AbstractHandler < Handler
  attr_writer :next_handler

  def next_handler(handler)
    @next_handler = handler

    handler
  end

  def handle(request)
    return @next_handler.handle(request) if @next_handler

    nil
  end
end



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

  autoload :FreshdeskHandler, 'freshdesk_handler'
  autoload :ChatgptHandler, 'chatgpt_handler'
  autoload :FileManagerHandler, 'file_manager_handler'
  autoload :ConsoleHandler, 'console_handler'

  def looking_what_is_new
    freshdesk = FreshdeskHandler.new(ENV["FRESH_API_KEY"])
    gpt = ChatgptHandler.new(ENV["CHATGPT_API_KEY"])
    file_manager = FileManagerHandler.new
    console_interaction = ConsoleHandler.new
    gpt_agent = ChatgptHandler.new(ENV["CHATGPT_API_KEY"], ENV["ASSISTANT_ID"])

    # pasos
    # 1.- tomar la data del ticket
    # 2.- resumirla con chatgpt
    # 3.- preguntar al usuario qué ticket trabajar
    # 4.- crear la carpeta
    #   4.1.- Esperar que el usuario cargue el archivo excel
    #   4.2.- extraer la data del archivo excel*
    #   4.3.- crear el csv formateado
    # 5.- enviar la data al agente chatgpt
    #   5.1.- usar la respuesta del agente para prepara el template
    #   5.2.- enviar el template al agente
    # 6.- crear el archivo en la ruta de centras de buk
    
    
    # en FileManager crear el mètodo get_template, ver como lo responde el asistente ( done )
    
    # estamos aquí
    # limpiar la data del csv
    # parametrizar los nombres de paises
    # crear todas las opciones de templates

    # opcional
    # parameterizar el nombre de la carpeta (tomar sólo el id del ticket)


    freshdesk.next_handler(gpt).next_handler(console_interaction).next_handler(file_manager).next_handler(gpt_agent).next_handler(file_manager)
    freshdesk.handle
  end
end
