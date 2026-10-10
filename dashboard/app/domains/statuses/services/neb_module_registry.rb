# frozen_string_literal: true

module Statuses
  module Services
    # Adopts Nagios Event Broker (NEB) module loader and callback registry from base/nebmods.c
    # Manages runtime plugin extensions, lifecycle initialization, and callback dispatching.
    class NebModuleRegistry
      NebModule = Struct.new(
        :id,
        :name,
        :version,
        :author,
        :description,
        :enabled,
        :callbacks,
        keyword_init: true
      ) do
        def enabled?
          enabled == true
        end
      end

      class << self
        def instance
          @instance ||= new
        end

        def register_module(name:, version: '1.0.0', author: '', description: '', &setup_block)
          instance.register_module(
            name: name,
            version: version,
            author: author,
            description: description,
            &setup_block
          )
        end

        def dispatch_event(event_type, payload = {})
          instance.dispatch_event(event_type, payload)
        end

        def modules
          instance.modules
        end

        def clear!
          instance.clear!
        end
      end

      def initialize
        @modules = {}
        @callbacks = Hash.new { |h, k| h[k] = [] }
        @mutex = Mutex.new
        @next_id = 1
      end

      # Registers a NEB module and executes its setup block
      def register_module(name:, version: '1.0.0', author: '', description: '', &setup_block)
        mod_key = name.to_s.downcase

        @mutex.synchronize do
          mod = NebModule.new(
            id: @next_id,
            name: name,
            version: version,
            author: author,
            description: description,
            enabled: true,
            callbacks: []
          )
          @next_id += 1
          @modules[mod_key] = mod

          # Context for registering callbacks within the module
          if block_given?
            binder = ModuleCallbackBinder.new(mod, @callbacks)
            binder.instance_eval(&setup_block)
          end

          mod
        end
      end

      # Dispatches NEB event to all registered and active module callbacks
      def dispatch_event(event_type, payload = {})
        ev_sym = event_type.to_sym
        handlers = []

        @mutex.synchronize do
          handlers = @callbacks[ev_sym].select { |cb| cb[:module].enabled? }
        end

        results = []
        handlers.each do |cb|
          res = cb[:proc].call(payload)
          results << { module: cb[:module].name, result: res }
        rescue StandardError => e
          Rails.logger.error("[NEB] Callback error in module '#{cb[:module].name}': #{e.message}")
        end

        results
      end

      def modules
        @mutex.synchronize { @modules.values }
      end

      def enable_module(name)
        @mutex.synchronize { @modules[name.to_s.downcase]&.enabled = true }
      end

      def disable_module(name)
        @mutex.synchronize { @modules[name.to_s.downcase]&.enabled = false }
      end

      def clear!
        @mutex.synchronize do
          @modules.clear
          @callbacks.clear
        end
      end

      # DSL helper for module registration block
      class ModuleCallbackBinder
        def initialize(mod, callback_map)
          @mod = mod
          @callback_map = callback_map
        end

        def on(event_type, &block)
          return unless block_given?

          @mod.callbacks << event_type.to_sym
          @callback_map[event_type.to_sym] << { module: @mod, proc: block }
        end
      end
    end
  end
end
