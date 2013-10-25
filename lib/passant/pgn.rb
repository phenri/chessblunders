require 'date'

module Passant

  module PGN
    CommentRegexp = /\{([^}]*)\}|;(.*)$/

    # A PGN tagpair
    class TagPair
      attr_accessor :value
      attr_reader :key

      def initialize(key, value)
        @key, @value = key, value
      end

      def self.required
        [ TagPair.new('Event',  'casual game'),
          TagPair.new('Site',   '?'),
          TagPair.new('Date',   Date.today.strftime('%Y.%m.%d')),
          TagPair.new('Round',  '?'),
          TagPair.new('White',  '?'),
          TagPair.new('Black',  '?'),
          TagPair.new('Result', '*') ]
      end
      def to_pgn; "[#{@key} \"#{@value}\"]" end
    end

    # Reflects a single PGN game that converts to a GameBoard
    class Game
      attr_reader :title, :tag_pairs

      def initialize(tag_pair_data, movetext)
        @movetext = movetext
        @tag_pairs = tag_pair_data.map do |tp|
          tp =~ /^\[([^\s]+)\s+"(.*)"\]$/
          TagPair.new($1, ($2 || ''))
        end
        set_title
      end

      def to_board(board=nil)
        board ||= GameBoard.new
        board.tag_pairs = self.tag_pairs
        move_data = @movetext.split(/[0-9]+\.{3}|[0-9]+\./)
        move_data.each {|md| Game.parse_turn_or_ply(md, board)}
        board
      end

      def tag_value(key)
        if tag = tag_pairs.find{|tp| tp.key.downcase == key.downcase}
          tag.value
        else
          nil
        end
      end

      # parses a turn or ply of movetext, e.g.
      # * 'e4'
      # * 'e4 e5'
      # * 'e4 {a comment}'
      # * 'e4 {a comment} e5'
      # * 'e4 e5 {a comment}'
      # * 'e4 ; a comment'
      # * 'e4 e5 ; a comment'
      # * 'e4 {a comment} e5 {second comment}'
      # * 'e4 {a comment} e5 ; second comment'
      def self.parse_turn_or_ply(str, board)
        return if str.length == 0

        first_move, rest = str.split(' ', 2)
        second_move = rest ? rest.gsub(/\{[^\}]*\}/, '').split(' ', 2).first : nil

        if second_move.nil? || second_move == ''
          comment1_match = str.strip.match(/{([^}]*)}/)
        else
          comment1_match = str.strip.match(/{([^}]*)}.+/)
        end

        comment1 = comment1_match ? comment1_match[1] : nil

        comment2_match = str.strip.match(/{([^}]*)}$/)
        comment2 = comment2_match ? comment2_match[1] : nil

        ply(board, first_move, comment1)
        ply(board, second_move, comment2) unless second_move.nil? || second_move == ''
      rescue => e
        binding.pry
      end

      private

      def self.ply(board, movetext, comment=nil)
        movetext.gsub!(/0-1|1-0|1\/2-1\/2/, '')
        movetext.strip!
        return if movetext.empty?
        mv = board.move(movetext)
        mv.comment = comment.strip if comment
      end

      def set_title
        @title = format("%s %s: %s %s",
                        tag_pairs[2].value,
                        tag_pairs[0].value,
                        (tag_pairs[4].value.split(',').first + ' vs. '+
                        tag_pairs[5].value.split(',').first),
                        tag_pairs[6].value)
      end
    end

    # Reflects a PGN file which can contain multiple games.
    # See: http://en.wikipedia.org/wiki/Pgn
    class File
      def initialize(path)
        @file = ::File.new(path)
      end

      def games
        @games ||= begin
          games = []
          tag_pairs = []
          movetext = ''

          while line = @file.gets
            line.strip!
            next if line[0,1] == '%'

            if line[0,1] == '['
              tag_pairs << line
            elsif line.length == 0
              if tag_pairs.length > 0 and movetext.length > 0
                games << Game.new(tag_pairs, movetext)
                tag_pairs = []
                movetext = ''
              end
            else
              movetext += (line + ' ')
            end
          end

          if tag_pairs.length > 0 and movetext.length > 0
            games << Game.new(tag_pairs, movetext)
          end

          games
        end
      end
    end

    # PGN support for a board
    module Support
      def tag_pairs
        @tag_pairs ||= TagPair.required
      end
      def tag_pairs=(pairs); @tag_pairs = pairs end

      def pgn_result; self.tag_pairs[6].value end
      def pgn_result=(r); self.tag_pairs[6].value = r end

      def movetext_array
        movetext_arr = []

        (@history.size.to_f / 2).ceil.times do |turn|
          turn_arr = []
          turn_arr << "#{turn+1}. "
          turn_arr << @history[turn*2].to_pgn

          if @history[(turn*2)+1]
            if @history[turn*2].comment
              turn_arr << "#{turn+1}... #{@history[(turn*2)+1].to_pgn}"
            else
              turn_arr << @history[(turn*2)+1].to_pgn
            end
          end
          movetext_arr << turn_arr
        end

        movetext_arr
      end

      def movetext
        movetext = ''
        movedata = movetext_array.map do |md|
          str = "#{md[0]}#{md[1]} "
          str += "#{md[2]} " if md[2]
          str
        end

        row = ''
        movedata.each do |md|
          if (row + md).length < 80
            row += md
          else
            movetext += (row + "\n")
            row = md
          end
        end
        movetext += row
        movetext
      end

      def to_pgn
        pgn = tag_pairs.map{|t| t.to_pgn}.join("\n") + "\n\n"
        pgn += movetext
        pgn
      end
    end
  end
end
