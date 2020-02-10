require "shopify_graphql_client/version"
require "graphql/client"
require "shopify_api"

module ShopifyGraphQLClient
  class Error < StandardError; end
  class GraphQLError < Error; end
  class ThrottledError < Error; end

  class << self
    def parse(str, filename=nil, lineno=nil)
      if filename.nil? && lineno.nil?
        location = caller_locations(1, 1).first
        filename = location.path
        lineno = location.lineno
      end

      client.parse(str, filename=filename, lineno=lineno)
    end

    def client
      @client ||= GraphQL::Client.new(schema: schema, execute: Executor.new).tap do |client|
        client.allow_dynamic_queries = true
      end
    end

    def query(*args)
      result = client.query(*args)
      errors = result.errors

      if result.errors&.any?
        messages = result.errors.messages.map do |path, messages|
          if messages.length > 0
            messages = messages.map{|message| "  - #{message}"}
            "#{path}:\n" + messages.join("\n")
          else
            "#{path}: #{messages.first}"
          end
        end
        if messages.join("\n") =~ /throttled/i 
          sleep(10)
          query(*args)
        else
          raise GraphQLError, messages.join("\n")
        end
      else
        result
      end
    end

    private

    def schema
      @schema ||= load_schema
    end

    def load_schema
      raise Error, "The schema file does not exist at #{schema_path}" unless File.exist?(schema_path)
      puts "Loading the local schema.json attached to this gem"
      GraphQL::Client.load_schema(schema_path)
    end

    def schema_path
      File.join(__dir__, '../schema.json')
    end
  end

  class Executor < GraphQL::Client::HTTP
    # avoid initializing @uri
    def initialize; end

    def headers(_context)
      ShopifyAPI::Base.headers
    end

    def uri
      ShopifyAPI::Base.site.dup.tap do |uri|
        uri.path = "/admin/api/2020-01/graphql.json"
      end
    end
  end
end
