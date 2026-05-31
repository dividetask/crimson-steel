module Abilities
  # Safe arithmetic evaluator for the Formula strings embedded in
  # abilities data (Range Formulas, Target Formulas, Effect Hash
  # entries, damage expressions, Modifier `add` values).
  #
  # Grammar (recursive descent):
  #   expr   := term (('+' | '-') term)*
  #   term   := factor (('*' | '/') factor)*
  #   factor := number | identifier | '(' expr ')' | '-' factor
  #
  # Division floors (round down) per the project convention that all
  # formula division uses floor(). Identifiers resolve against the
  # supplied bindings; an unbound identifier raises NameError so callers
  # that legitimately defer a variable (e.g. `success` before a Roll)
  # can rescue it.
  module Formula
    class UnresolvedName < NameError; end

    module_function

    def evaluate(expr, bindings = {})
      ctx = {}
      bindings.each { |k, v| ctx[k.to_s] = v }
      tokens = tokenize(expr.to_s)
      parser = Parser.new(tokens, ctx)
      result = parser.parse!
      to_number(result)
    end

    def tokenize(str)
      tokens = []
      scanner = str.dup
      until scanner.empty?
        case scanner
        when /\A\s+/
          scanner = scanner[$~[0].length..]
        when /\A\d+(?:\.\d+)?/
          tok = $~[0]
          tokens << [:num, tok.include?('.') ? tok.to_f : tok.to_i]
          scanner = scanner[tok.length..]
        when /\A[A-Za-z_][A-Za-z0-9_]*/
          tokens << [:id, $~[0]]
          scanner = scanner[$~[0].length..]
        when /\A[+\-*\/()]/
          tokens << [:op, $~[0]]
          scanner = scanner[1..]
        else
          raise ArgumentError, "unexpected character in formula: #{scanner.inspect}"
        end
      end
      tokens
    end

    def to_number(value)
      return value.to_i if value.is_a?(Float) && value == value.to_i
      value
    end

    # Recursive-descent parser over the token list.
    class Parser
      def initialize(tokens, bindings)
        @tokens = tokens
        @pos = 0
        @bindings = bindings
      end

      def parse!
        value = expr
        raise ArgumentError, "trailing tokens in formula: #{@tokens[@pos..].inspect}" if @pos < @tokens.length
        value
      end

      private

      def peek
        @tokens[@pos]
      end

      def take
        tok = @tokens[@pos]
        @pos += 1
        tok
      end

      def op?(sym)
        t = peek
        t && t[0] == :op && t[1] == sym
      end

      def expr
        value = term
        while op?('+') || op?('-')
          o = take[1]
          rhs = term
          value = (o == '+') ? value + rhs : value - rhs
        end
        value
      end

      def term
        value = factor
        while op?('*') || op?('/')
          o = take[1]
          rhs = factor
          value = (o == '*') ? value * rhs : (value / rhs).floor
        end
        value
      end

      def factor
        if op?('-')
          take
          return -factor
        end
        if op?('(')
          take
          value = expr
          raise ArgumentError, 'unbalanced parentheses in formula' unless op?(')')
          take
          return value
        end
        tok = take
        raise ArgumentError, 'unexpected end of formula' if tok.nil?
        case tok[0]
        when :num
          tok[1]
        when :id
          unless @bindings.key?(tok[1])
            raise UnresolvedName, "unresolved name in formula: #{tok[1]}"
          end
          @bindings[tok[1]]
        else
          raise ArgumentError, "unexpected token in formula: #{tok.inspect}"
        end
      end
    end
  end
end
