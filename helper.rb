module Helper
require 'colorize'
  def get_color(value)
    case value
    when String
      :light_blue
    when Numeric
      :light_cyan
    when Symbol
      :cyan
    when true, false
      :light_magenta
    else
      :white
    end
  end
end