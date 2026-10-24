# frozen_string_literal: true

require "zlib"

# Where a language's kaikki.org extract comes from — its URL, or a local
# .jsonl.gz (tests, offline imports) — read as text lines while it
# downloads: nothing but the current chunk is kept.
#
#   source = Lexicon::Source.new(url: language.url)
#   source.head        # => { etag:, last_modified:, size: }
#   source.each_line { |line| … }
#   source.bytes_read  # compressed bytes received
#
# A broken download raises Lexicon::Source::Error naming what broke: the
# HTTP status, a short read (bytes ≠ Content-Length) or a gzip stream that
# ends early.
module Lexicon
  class Source < ApplicationClient
    class Error < ApplicationClient::Error; end

    REDIRECTS = 3
    TIMEOUT = 60 # an extract is hundreds of megabytes

    attr_reader :url, :path, :bytes_read, :expected_bytes

    # store_to: where a download from url is kept (Lexicon::Downloads) — only
    # once it's complete; a broken one never replaces the file there.
    def initialize(url: nil, path: nil, store_to: nil)
      @url = url
      @path = path.presence && Pathname(path)
      @store_to = store_to.presence && Pathname(store_to)
      @bytes_read = 0
    end

    def local? = @path.present?
    def label = local? ? @path.to_s : @url

    # The server's headers for it (a local file: its size and mtime).
    def head
      if local?
        raise Error, "no such file: #{@path}" unless @path.file?

        return { etag: "file:#{@path.size}:#{@path.mtime.to_i}", last_modified: @path.mtime, size: @path.size }
      end

      response = request(Net::HTTP::Head, URI(@url))
      { etag: response["etag"], last_modified: response["last-modified"].presence && Time.httpdate(response["last-modified"]),
        size: response["content-length"]&.to_i }
    end

    PEEK_LINES = 200

    # The language of the extract, from its first entries — reading only the
    # start of the download: { code: "es", language: "Spanish" }.
    def peek
      seen = 0
      each_line do |line|
        seen += 1
        data = parsed(line)
        return { code: data["lang_code"], language: data["lang"] } if data.is_a?(Hash) && data["lang_code"].present?
        break if seen >= PEEK_LINES
      end
      raise Error, "no language code in the first #{seen} lines — is this a kaikki.org extract?"
    end

    # A line of the extract read as JSON; nil for one that isn't JSON.
    def parsed(line)
      JSON.parse(line)
    rescue JSON::ParserError
      nil
    end

    # Each decompressed line, as UTF-8.
    def each_line
      inflater = Zlib::Inflate.new(Zlib::MAX_WBITS + 32)
      buffer = +""
      saving = start_saving
      each_chunk do |chunk|
        @bytes_read += chunk.bytesize
        saving&.write(chunk)
        buffer << inflater.inflate(chunk)
        last = buffer.rindex("\n")
        next if last.nil?

        # One cut per chunk: slicing line by line off the front would move the rest every time.
        buffer.slice!(0..last).force_encoding(Encoding::UTF_8).each_line { yield _1 }
      end
      if @expected_bytes && @bytes_read != @expected_bytes
        raise Error, "the download stopped early: #{@bytes_read} of #{@expected_bytes} bytes"
      end
      raise Error, "the gzip stream ended early (truncated or not a .gz file)" unless inflater.finished?

      buffer << inflater.finish
      yield buffer.force_encoding(Encoding::UTF_8) unless buffer.empty?
      finish_saving(saving)
    rescue Zlib::Error => e
      raise Error, "not a valid gzip stream after #{@bytes_read} bytes: #{e.message}"
    ensure
      inflater&.close
      if saving && !saving.closed?
        saving.close
        FileUtils.rm_f(saving.path)
      end
    end

    private

    # Only a download is kept, never a local file read.
    def start_saving
      return if local? || @store_to.nil?

      FileUtils.mkdir_p(@store_to.dirname)
      File.open("#{@store_to}.part", "wb")
    end

    def finish_saving(saving)
      return unless saving

      saving.close
      File.rename(saving.path, @store_to)
    end

    def each_chunk(&block)
      if local?
        raise Error, "no such file: #{@path}" unless @path.file?

        @expected_bytes = @path.size
        File.open(@path, "rb") do |file|
          while (chunk = file.read(1 << 16))
            yield chunk
          end
        end
      else
        request(Net::HTTP::Get, URI(@url)) do |response|
          @expected_bytes = response["content-length"]&.to_i
          response.read_body(&block)
        end
      end
    end

    # Follows a few redirects; a block reads the answer as it streams.
    def request(klass, uri, redirects = REDIRECTS, &block)
      perform(klass.new(uri), service: uri.host) do |response|
        case response
        when Net::HTTPRedirection
          raise Error, "too many redirects from #{@url}" if redirects.zero?

          return request(klass, URI.join(uri, response["location"]), redirects - 1, &block)
        when Net::HTTPSuccess
          block ? yield(response) : (return response)
        else
          raise Error, "#{uri} answered #{response.code} #{response.message}"
        end
      end
    end
  end
end
