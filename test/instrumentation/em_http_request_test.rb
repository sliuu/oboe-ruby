# Copyright (c) 2015 AppNeta, Inc.
# All rights reserved.

require 'minitest_helper'

# Disable this test on JRuby until we can investigate
# "SOCKET: SET COMM INACTIVITY UNIMPLEMENTED 10"
# https://travis-ci.org/appneta/traceview-ruby/jobs/33745752
if RUBY_VERSION >= '1.9' and TraceView::Config[:em_http_request][:enabled] and not defined?(JRUBY_VERSION)

  describe "EventMachine" do
    before do
      clear_all_traces
      @collect_backtraces = TraceView::Config[:em_http_request][:collect_backtraces]
    end

    after do
      TraceView::Config[:em_http_request][:collect_backtraces] = @collect_backtraces
    end

    it 'EventMachine::HttpConnection should be loaded, defined and ready' do
      defined?(::EventMachine::HttpConnection).wont_match nil
    end

    it 'should have traceview methods defined' do
      ::EventMachine::HttpConnection.method_defined?("setup_request_with_traceview").must_equal true
    end

    it 'should trace request' do
      TraceView::API.start_trace('em-http-request_test', '', {}) do
        EventMachine.run do
          http = EventMachine::HttpRequest.new('http://appneta.com/').get
          http.callback do
            EventMachine.stop
          end
        end
      end

      traces = get_all_traces

      traces.count.must_equal 4
      validate_outer_layers(traces, 'em-http-request_test')

      traces[1]["Layer"].must_equal "em-http-request"
      traces[1]["Label"].must_equal "entry"
      traces[1]["IsService"].must_equal "1"
      traces[1]["RemoteURL"].must_equal "http://appneta.com/"
      traces[1].has_key?('Backtrace').must_equal TraceView::Config[:em_http_request][:collect_backtraces]

      traces[2]["Layer"].must_equal "em-http-request"
      traces[2]["Label"].must_equal "exit"
      traces[2]["Async"].must_equal "1"
      traces[2].has_key?('Backtrace').must_equal TraceView::Config[:em_http_request][:collect_backtraces]
    end

    it "should obey :collect_backtraces setting when true" do
      TraceView::Config[:em_http_request][:collect_backtraces] = true

      TraceView::API.start_trace('em-http-request_test', '', {}) do
        EventMachine.run do
          http = EventMachine::HttpRequest.new('http://appneta.com/').get
          http.callback do
            EventMachine.stop
          end
        end
      end

      traces = get_all_traces
      layer_has_key(traces, 'em-http-request', 'Backtrace')
    end

    it "should obey :collect_backtraces setting when false" do
      TraceView::Config[:em_http_request][:collect_backtraces] = false

      TraceView::API.start_trace('em-http-request_test', '', {}) do
        EventMachine.run do
          http = EventMachine::HttpRequest.new('http://appneta.com/').get
          http.callback do
            EventMachine.stop
          end
        end
      end

      traces = get_all_traces
      layer_doesnt_have_key(traces, 'em-http-request', 'Backtrace')
    end
  end

end # unless defined?(JRUBY_VERSION)
