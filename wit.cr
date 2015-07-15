#require 'wit/Parser'
require "./wit/Parser"

#lexer = Wit::Scanner::Scanner.new
#loop do
#    begin
#        puts lexer.next.to_s
#    rescue Wit::EOFError
#        exit
#    rescue ex : Wit::LexError
#        puts "lexer error at #{ex.lineno}:#{ex.colno}"
#        raise ex
#    end
#end

#Wit::Parser.new(STDIN).program
begin
  Wit::Parser::Parser.new.parse_program
rescue ex : Wit::ParseError
  puts "#{ex.lineno}:#{ex.colno}: error: #{ex.to_s}"
end
