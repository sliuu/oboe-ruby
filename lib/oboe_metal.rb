# Copyright (c) 2013 AppNeta, Inc.
# All rights reserved.

# Disable docs and Camelcase warns since we're implementing
# an interface here.  See OboeBase for details.
# rubocop:disable Style/Documentation, Style/MethodName
module TraceView
  extend TraceViewBase
  include Oboe_metal

  class Reporter
    ##
    # Initialize the TraceView Context, reporter and report the initialization
    #
    def self.start
      return unless TraceView.loaded

      begin
        Oboe_metal::Context.init

        if ENV.key?('TRACEVIEW_GEM_TEST')
          TraceView.reporter = TraceView::FileReporter.new('/tmp/trace_output.bson')
        else
          TraceView.reporter = TraceView::UdpReporter.new(TraceView::Config[:reporter_host], TraceView::Config[:reporter_port])
        end

        # Only report __Init from here if we are not instrumenting a framework.
        # Otherwise, frameworks will handle reporting __Init after full initialization
        unless defined?(::Rails) || defined?(::Sinatra) || defined?(::Padrino) || defined?(::Grape)
          TraceView::API.report_init unless ENV.key?('TRACEVIEW_GEM_TEST')
        end

      rescue => e
        $stderr.puts e.message
        raise
      end
    end

    def self.sendReport(evt)
      TraceView.reporter.sendReport(evt)
    end

    ##
    # clear_all_traces
    #
    # Truncates the trace output file to zero
    #
    def self.clear_all_traces
      File.truncate($trace_file, 0)
    end

    ##
    # get_all_traces
    #
    # Retrieves all traces written to the trace file
    #
    def self.get_all_traces
      io = File.open($trace_file, 'r')
      contents = io.readlines(nil)

      return contents if contents.empty?

      s = StringIO.new(contents[0])

      traces = []

      until s.eof?
        if ::BSON.respond_to? :read_bson_document
          traces << BSON.read_bson_document(s)
        else
          traces << BSON::Document.from_bson(s)
        end
      end

      traces
    end
  end

  class Event
    def self.metadataString(evt)
      evt.metadataString
    end
  end

  class << self
    def sample?(opts = {})
      begin
        return false unless TraceView.always? && TraceView.loaded

        # Assure defaults since SWIG enforces Strings
        layer   = opts[:layer]      ? opts[:layer].strip      : ''
        xtrace  = opts[:xtrace]     ? opts[:xtrace].strip     : ''
        tv_meta = opts['X-TV-Meta'] ? opts['X-TV-Meta'].strip : ''

        rv = TraceView::Context.sampleRequest(layer, xtrace, tv_meta)

        if rv == 0
          if ENV.key?('TRACEVIEW_GEM_TEST')
            # When in test, always trace and don't clear
            # the stored sample rate/source
            true
          else
            TraceView.sample_rate = -1
            TraceView.sample_source = -1
            false
          end
        else
          # liboboe version > 1.3.1 returning a bit masked integer with SampleRate and
          # source embedded
          TraceView.sample_rate = (rv & SAMPLE_RATE_MASK)
          TraceView.sample_source = (rv & SAMPLE_SOURCE_MASK) >> 24
          true
        end
      rescue StandardError => e
        TraceView.logger.debug "[oboe/error] sample? error: #{e.inspect}"
        false
      end
    end

    def set_tracing_mode(mode)
      return unless TraceView.loaded

      value = mode.to_sym

      case value
      when :never
        TraceView::Context.setTracingMode(OBOE_TRACE_NEVER)

      when :always
        TraceView::Context.setTracingMode(OBOE_TRACE_ALWAYS)

      when :through
        TraceView::Context.setTracingMode(OBOE_TRACE_THROUGH)

      else
        TraceView.logger.fatal "[oboe/error] Invalid tracing mode set: #{mode}"
        TraceView::Context.setTracingMode(OBOE_TRACE_THROUGH)
      end
    end

    def set_sample_rate(rate)
      return unless TraceView.loaded

      # Update liboboe with the new SampleRate value
      TraceView::Context.setDefaultSampleRate(rate.to_i)
    end
  end
end
# rubocop:enable Style/Documentation

TraceView.loaded = true
