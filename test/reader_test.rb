# encoding: utf-8

require_relative 'helper'

module ReaderTests

  def silent
    verbose, $VERBOSE = $VERBOSE, false

    begin
      yield
    ensure
      $VERBOSE = verbose
    end
  end

  def with_external_encoding(encoding)
    original_encoding = Encoding.default_external

    begin
      silent { Encoding.default_external = Encoding.find(encoding) }
      yield
    ensure
      silent { Encoding.default_external = original_encoding }
    end
  end

  def test_false_on_empty_buffer
    assert_equal false, @reader.gets
  end

  def test_nil
    @reader.feed("$-1\r\n")
    assert_nil @reader.gets
  end

  def test_integer
    value = 2**63-1 # largest 64-bit signed integer
    @reader.feed(":#{value.to_s}\r\n")
    assert_equal value, @reader.gets
  end

  def test_status_string
    @reader.feed("+status\r\n")
    assert_equal "status", @reader.gets
  end

  def test_error_string
    @reader.feed("-error\r\n")
    error = @reader.gets

    assert_equal RuntimeError, error.class
    assert_equal "error", error.message
  end

  def test_errors_in_nested_multi_bulk
    @reader.feed("*2\r\n-err0\r\n-err1\r\n")
    errors = @reader.gets

    2.times do |i|
      assert_equal RuntimeError, errors[i].class
      assert_equal "err#{i}", errors[i].message
    end
  end

  def test_empty_bulk_string
    @reader.feed("$0\r\n\r\n")
    assert_equal "", @reader.gets
  end

  def test_bulk_string
    @reader.feed("$5\r\nhello\r\n")
    assert_equal "hello", @reader.gets
  end

  def test_bulk_string_encoding
    string = "שלום"
    protocol = "$%d\r\n%s\r\n" % [string.bytesize, string]
    protocol.force_encoding "ASCII-8BIT"

    @reader.feed(protocol)

    with_external_encoding("UTF-8") do
      assert_equal string, @reader.gets
    end
  end

  def test_bulk_string_encoding_chunked
    string = "שלום"
    protocol = "$%d\r\n%s\r\n" % [string.bytesize, string]
    protocol.force_encoding "ASCII-8BIT"

    protocol.each_char do |c|
      @reader.feed(c)
    end

    with_external_encoding("UTF-8") do
      assert_equal string, @reader.gets
    end
  end

  def test_null_multi_bulk
    @reader.feed("*-1\r\n")
    assert_nil @reader.gets
  end

  def test_empty_multi_bulk
    @reader.feed("*0\r\n")
    assert_equal [], @reader.gets
  end

  def test_multi_bulk
    @reader.feed("*2\r\n$5\r\nhello\r\n$5\r\nworld\r\n")
    assert_equal ["hello", "world"], @reader.gets
  end

  def test_nested_multi_bulk
    @reader.feed("*2\r\n*2\r\n$5\r\nhello\r\n$5\r\nworld\r\n$1\r\n!\r\n")
    assert_equal [["hello", "world"], "!"], @reader.gets
  end

  def test_nested_multi_bulk_redux
    @reader.feed("*2\r\n*2\r\n*1\r\n$5\r\nhello\r\n$5\r\nworld\r\n$1\r\n!\r\n")
    assert_equal [[["hello"], "world"], "!"], @reader.gets
  end
end

if defined?(Hiredis::Ruby::Reader)
  class RubyReaderTest < Minitest::Test
    include ReaderTests

    def setup
      @reader = Hiredis::Ruby::Reader.new
    end
  end
end

if defined?(Hiredis::Ext::Reader)
  class ExtReaderTest < Minitest::Test
    include ReaderTests

    def setup
      @reader = Hiredis::Ext::Reader.new
    end
  end
end
