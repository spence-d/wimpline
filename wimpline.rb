#!/usr/bin/env ruby

require 'optparse'
require 'socket'

params = {}
OptionParser.new do |opts|
  opts.on '-r', '--right-oriented', 'Arrows go the other direction'
  opts.on '-pNUM', '--padding NUM', Integer, 'Amount of padding between segments'
  opts.on '-dCHAR', '--divider CHAR', String, 'String to separate segments'
  opts.on '-wNUM', '--width NUM', Integer, 'Maximum number of columns to occupy'
end.parse! into: params

class Segment
  attr_reader :background, :second_background, :foreground, :second_foreground,
              :body, :show, :bold, :short

  def initialize options
    @background = options[:background] || '0'
    @second_background = options[:second_background] || '0'
    @foreground = options[:foreground]
    @second_foreground = options[:second_foreground]
    @body = options[:body] || ''
    @show = options[:show] || false
    @bold = options[:bold] || false
    @short = options[:short] || false
  end
end

class Path < Segment
  def initialize max_nodes, options = {}
    @max_nodes = max_nodes || 6
    super options
  end

  def body
    path = Dir.pwd
    home = File.expand_path('~')
    path.sub!(/^#{home}/, '~')
    *dirs, last = path.split '/'
    return path if dirs.empty?
    if dirs.size > @max_nodes
      length = dirs.size - @max_nodes
      dirs[1, length] = '…'
    end
    if short
      abbreviated_dirs = dirs.map do |dir|
        if dir.empty?
          ''
        else
          dir[0]
        end
      end
      File.join(abbreviated_dirs + [last])
    else
      File.join dirs, last
    end
  end
end

class EnvVar < Segment
  attr_reader :body
  def initialize name, options
    super options
    @body = ENV[name] || ''
  end
end

class ViMode < Segment
  MODES = {
    'viins'  => "INSERT",
    'main'   => "INSERT",
    'vicmd'  => "NORMAL",
    'viopp'  => "WAITNG",
    'visual' => "VISUAL",
  }

  def initialize mode, options
    @mode = mode
    super options
  end

  def body
    if not show and @mode == 'vicmd'
      ''
    else
      mode = MODES[@mode] || '      '
      if short
        mode[0]
      else
        mode
      end
    end
  end

  def background
    if @mode == 'vicmd'
      super
    else
      second_background
    end
  end

  def foreground
    if @mode == 'vicmd'
      super || '0'
    else
      second_foreground || '0'
    end
  end

  def bold
    true
  end
end

class ExitCode < Segment
  MESSAGES = {
    0 => 'OK',
    1 => 'ERROR',
    2 => 'USAGE',

    64 => 'EX_USAGE',
    65 => 'EX_DATAERR',
    66 => 'EX_NOINPUT',
    67 => 'EX_NOUSER',
    68 => 'EX_NOHOST',
    69 => 'EX_UNAVAILABLE',
    70 => 'EX_SOFTWARE',
    71 => 'EX_OSERR',
    72 => 'EX_OSFILE',
    73 => 'EX_CANTCREAT',
    74 => 'EX_IOERR',
    75 => 'EX_TEMPFAIL',
    76 => 'EX_PROTOCOL',
    77 => 'EX_NOPERM',
    78 => 'EX_CONFIG',

    126 => 'NOPERM',
    127 => 'NOTFOUND',
    128 => 'BADERR',

    129 => 'SIGHUP',
    130 => 'SIGINT',
    131 => 'SIGQUIT',
    132 => 'SIGILL',
    133 => 'SIGTRAP',
    134 => 'SIGABRT',
    135 => 'SIGEMT',
    136 => 'SIGFPE',
    137 => 'SIGKILL',
    138 => 'SIGBUS',
    139 => 'SIGSEGV',
    140 => 'SIGSYS',
    141 => 'SIGPIPE',
    142 => 'SIGALRM',
    143 => 'SIGTERM',
    144 => 'SIGURG',
    145 => 'SIGSTOP',
    146 => 'SIGTSTP',
    147 => 'SIGCONT',
    148 => 'SIGCHLD',
    149 => 'SIGTTIN',
    150 => 'SIGTTOU',
    151 => 'SIGIO',
    152 => 'SIGXCPU',
    153 => 'SIGXFSZ',
    154 => 'SIGVTALRM',
    155 => 'SIGPROF',
    156 => 'SIGWINCH',
    157 => 'SIGINFO',
    158 => 'SIGUSR1',
    159 => 'SIGUSR2',

    255 => 'RANGE',
  }

  def initialize code, options
    options[:background] ||= 'green'
    super options
    @code = code
  end

  def body
    if @code.zero? and not show
      ''
    elsif short
      @code.to_s
    else
      MESSAGES[@code] || @code.to_s
    end
  end

  def bold
    case @code
    when 0
      super
    else
      true
    end
  end

  def background
    case @code
    when 0
      super
    else
      second_background || 'red'
    end
  end

  def foreground
    case @code
    when 0
      super
    else
      second_foreground || 'white'
    end
  end
end

class Hostname < Segment
  def initialize options
    super options
  end

  def body
    if show or ENV.has_key? 'SSH_CLIENT'
      host = Socket.gethostname
      if short
        host.split('.').first
      else
        host
      end
    else
      ''
    end
  end
end

class Empty < Segment
end

class Or
  def initialize seg1, seg2
    if seg1.body.empty?
      @segment = seg2
    else
      @segment = seg1
    end
  end

  def respond_to? method
    @segment.respond_to? method
  end

  def method_missing method, *args, &block
    if @segment.respond_to? method
      @segment.send method, *args, &block
    end
  end
end

class Segments
  def initialize segments, options
    @reverse = options[:'right-oriented'] || false
    @padding = ' ' * (options[:padding] || 1)
    @divider = options[:divider]
    @columns = options[:width]
    @segments = []
    segment_opts = {}
    segments.each do |segment|
      if segment.start_with? '-'
        flag = segment[1]
        little_flag = flag.downcase
        segment_opts[:short] = flag == little_flag
        value = segment[2..-1]
        case flag
        when 's'
          segment_opts[:show] = true
        when 'b'
          segment_opts[:bold] = true
        when 'k'
          segment_opts[:background] = value
        when 'f'
          segment_opts[:foreground] = value
        when 'K'
          segment_opts[:second_background] = value
        when 'F'
          segment_opts[:second_foreground] = value
        when 'h', 'H'
          @segments << Hostname.new(segment_opts)
          segment_opts = {}
        when 'x', 'X'
          @segments << ExitCode.new(value.to_i, segment_opts)
          segment_opts = {}
        when 'v', 'V'
          @segments << ViMode.new(value, segment_opts)
          segment_opts = {}
        when 'e', 'E'
          @segments << EnvVar.new(value, segment_opts)
          segment_opts = {}
        when '0'
          @segments << Empty.new(segment_opts)
          segment_opts = {}
        when 'o'
          @segments << Or.new(*@segments.pop(2))
          segment_opts = {}
        when 'd', 'D'
          if value.empty?
            max_nodes = nil
          else
            max_nodes = value.to_i
          end
          @segments << Path.new(max_nodes, segment_opts)
          segment_opts = {}
        end
      else
        segment_opts[:body] = segment
        @segments << Segment.new(segment_opts)
        segment_opts = {}
      end
    end
  end

  def to_s
    if @reverse
      divider = @divider || ''
      suffix = '%k'
    else
      divider = @divider || ''
      suffix = "#{divider}%f "
    end

    first = true

    @segments.map.with_index do |segment, i|
      next if not segment.is_a? Empty and segment.body.empty?

      body = segment.body
      padding = if segment.is_a? Empty
                  ''
                else
                  @padding
                end

      unless @columns.nil?
        columns = padding.length * 2 + body.length + 2
        next if columns > @columns
        @columns -= columns
      end

      if segment.bold
        body = "%B#{body}%b"
      end
      if not segment.foreground.nil?
        body = "%F{#{segment.foreground}}#{body}%f"
      end

      background = segment.background

      if @reverse
        s = "%F{#{background}}#{divider}%f%K{#{background}}#{padding}#{body}%f#{padding}"
      else
        div = if first
                ''
              else
                divider
              end
        s = "%K{#{background}}#{div}%f#{padding}#{body}#{padding}%F{#{background}}%k"
      end
      first = false
      s
    end.join + suffix
  end
end

segments = Segments.new ARGV, params
puts segments
