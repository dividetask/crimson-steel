module Creatures
  # Safe arithmetic-formula evaluator used by HP Formula, Mana Base
  # Formula, and Modifier `add` expressions. Accepts integer
  # literals, named variables, the operators + - * /, and parens.
  # Division is floor (round toward negative infinity) per the
  # project convention. Other tokens raise.
  module Formula
    module_function

    # eval('2 * con', con: 14) → 28
    # eval('con / 2', con: 15) → 7  (floor)
    def eval(expr, vars = {})
      tokens = tokenize(expr.to_s)
      parser = Parser.new(tokens, normalize_vars(vars))
      result = parser.expr
      raise ArgumentError, "trailing input in formula #{expr.inspect}" unless parser.done?
      result
    end

    def tokenize(src)
      tokens = []
      i = 0
      while i < src.length
        c = src[i]
        case c
        when ' ', "\t", "\n"
          i += 1
        when /\d/
          j = i
          j += 1 while j < src.length && src[j] =~ /\d/
          tokens << [:num, src[i...j].to_i]
          i = j
        when /[A-Za-z_]/
          j = i
          j += 1 while j < src.length && src[j] =~ /[A-Za-z_0-9]/
          tokens << [:ident, src[i...j]]
          i = j
        when '+', '-', '*', '/', '(', ')'
          tokens << [:op, c]
          i += 1
        else
          raise ArgumentError, "unexpected character #{c.inspect} in formula"
        end
      end
      tokens
    end

    def normalize_vars(vars)
      vars.each_with_object({}) { |(k, v), h| h[k.to_s] = v }
    end

    # Recursive-descent parser. expr = term (('+'|'-') term)*;
    # term = factor (('*'|'/') factor)*; factor = ['-' factor] |
    # NUMBER | IDENT | '(' expr ')'.
    class Parser
      def initialize(tokens, vars)
        @tokens = tokens
        @vars = vars
        @pos = 0
      end

      def done?
        @pos >= @tokens.length
      end

      def expr
        left = term
        while peek_op?('+', '-')
          op = advance[1]
          right = term
          left = (op == '+') ? left + right : left - right
        end
        left
      end

      def term
        left = factor
        while peek_op?('*', '/')
          op = advance[1]
          right = factor
          left = (op == '*') ? left * right : (left.to_f / right).floor
        end
        left
      end

      def factor
        if peek_op?('-')
          advance
          return -factor
        end
        if peek_op?('+')
          advance
          return factor
        end
        if peek_op?('(')
          advance
          v = expr
          raise ArgumentError, 'missing )' unless peek_op?(')')
          advance
          return v
        end
        tok = advance
        raise ArgumentError, 'unexpected end of formula' if tok.nil?
        case tok[0]
        when :num then tok[1]
        when :ident
          name = tok[1]
          raise ArgumentError, "unknown formula variable #{name.inspect}" unless @vars.key?(name)
          @vars[name]
        else
          raise ArgumentError, "unexpected token #{tok.inspect} in formula"
        end
      end

      def peek_op?(*ops)
        t = @tokens[@pos]
        t && t[0] == :op && ops.include?(t[1])
      end

      def advance
        t = @tokens[@pos]
        @pos += 1
        t
      end
    end
  end
end
