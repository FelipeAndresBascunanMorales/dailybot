#!/usr/bin/env ruby

require_relative 'dailybot'


def start
  daily_work = Dailybot.new
  daily_work.looking_what_is_new
end

if __FILE__ == $0
  start
end