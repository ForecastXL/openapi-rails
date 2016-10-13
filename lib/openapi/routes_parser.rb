module Openapi
  class RoutesParser
    require 'action_dispatch/routing/inspector'

    attr_accessor :routes

    def initialize(controller)
      @controller = controller
      formatter = ActionDispatch::Routing::ConsoleFormatter.new
      @routes_table = routes_inspector.format(formatter, controller_slug)
      @routes = parse!
    end

    private

    def rails_routes
      Rails.application.routes.routes
    end

    def routes_inspector
      ActionDispatch::Routing::RoutesInspector.new(rails_routes)
    end

    def controller_slug
      @controller.
        to_s.
        underscore.
        gsub('::', '/').
        gsub('_controller', '')
    end

    def parse!
      routes = @routes_table.split("\n")
      routes.shift

      routes.map do |row|
        row.remove! ' {:format=>:json}'
        action = row.sub(/.*?#/, '')
        route  = row.split(' ').reverse
        path   = route[1].gsub('(.:format)','')
        method = route[2].underscore

        [method, path, action]
      end.compact
    end
  end
end
