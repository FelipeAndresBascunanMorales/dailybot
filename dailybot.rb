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

  def looking_what_is_new
    fresh = FreshdeskConnection.new(ENV["FRESH_API_KEY"])
    tickets = fresh.get_tickets

    gpt = ChatgptConnection.new(ENV["CHATGPT_API_KEY"])
    tickets_summary = gpt.get_tickets_summary(tickets)
    tickets_summary.each do |ticket, v|
      puts ticket
    end
  end
end
