# Mongrel Web Server - A Mostly Ruby HTTP server and Library
#
# Copyright (C) 2005 Zed A. Shaw zedshaw AT zedshaw dot com
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

require 'test/unit'
require 'net/http'
require 'mongrel'
require 'timeout'
require File.dirname(__FILE__) + "/testhelp.rb"

class TestHandler < Mongrel::HttpHandler
  attr_reader :ran_test

  def process(request, response)
    @ran_test = true
    response.socket.write("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nhello!\n")
  end
end


class WebServerTest < Test::Unit::TestCase

  def setup
    @request = "GET / HTTP/1.1\r\nHost: www.zedshaw.com\r\nContent-Type: text/plain\r\n\r\n"
    # we set num_processors=1 so that we can test the reaping code
    @server = HttpServer.new("127.0.0.1", 9998,num_processors=1)
    @tester = TestHandler.new
    @server.register("/test", @tester)
    @server.run 
  end

  def teardown
    @server.stop
  end

  def test_simple_server
    hit(['http://localhost:9998/test'])
    assert @tester.ran_test, "Handler didn't really run"
  end


  def do_test(st, chunk, close_after=nil)
    s = TCPSocket.new("127.0.0.1", 9998);
    req = StringIO.new(st)
    nout = 0

    while data = req.read(chunk)
      nout += s.write(data)
      s.flush
      sleep 0.2
      if close_after and nout > close_after
        s.close_write
        sleep 1
      end
    end
    s.write(" ") if RUBY_PLATFORM =~ /mswin/
    s.close
  end

  def test_trickle_attack
    do_test(@request, 3)
  end

  def test_close_client
    assert_raises IOError do
      do_test(@request, 10, 20)
    end
  end

  def test_bad_client
    redirect_test_io do
      do_test("GET /test HTTP/BAD", 3)
    end
  end

  def test_header_is_too_long
    redirect_test_io do
      long = "GET /test HTTP/1.1\r\n" + ("X-Big: stuff\r\n" * 15000) + "\r\n"
      assert_raises Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNABORTED, Errno::EINVAL do
        do_test(long, long.length/2)
      end
    end
  end

  def test_num_processors_overload
    redirect_test_io do
      assert_raises Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNABORTED, Errno::EINVAL do
        tests = [
          Thread.new { do_test(@request, 1) },
          Thread.new { do_test(@request, 10) },
        ]

        tests.each {|t| t.join}
      end
    end
  end

  def test_file_streamed_request
    body = "a" * (Mongrel::Const::MAX_BODY * 2)
    long = "GET /test HTTP/1.1\r\nContent-length: #{body.length}\r\n\r\n" + body
    do_test(long, Mongrel::Const::CHUNK_SIZE * 2 -400)
  end

end

