module PolymorphicIntegerType

  module Extensions
    module ClassMethods

      def belongs_to(name, options = {})
        integer_type = options.delete :integer_type
        super
        if options[:polymorphic] && integer_type
          mapping = PolymorphicIntegerType::Mapping[name]
          foreign_type = reflections[name].foreign_type
          self._polymorphic_foreign_types << foreign_type

          define_method foreign_type do
            t = super()
            mapping[t]
          end

          define_method "#{foreign_type}=" do |klass|
            enum = mapping.key(klass.to_s)
            enum ||= mapping.key(klass.base_class.to_s) if klass.kind_of?(Class) && klass <= ActiveRecord::Base
            enum ||= klass if klass != NilClass
            super(enum)
          end

          define_method "#{name}=" do |record|
            super(record)
            send("#{foreign_type}=", record.class)
          end

          validate do
            t = send(foreign_type)
            unless t.nil? || mapping.values.include?(t)
              errors.add(foreign_type, "is not included in the mapping")
            end
          end
        end
      end

      def remove_type_and_establish_mapping(name, options)
        integer_type = options.delete :integer_type
        if options[:as] && integer_type
          poly_type = options.delete(:as)
          mapping = PolymorphicIntegerType::Mapping[poly_type]
          klass_mapping = (mapping||{}).key self.sti_name
          raise "Polymorphic Class Mapping is missing for #{poly_type}" unless klass_mapping

          options[:foreign_key] ||= "#{poly_type}_id"
          foreign_type = options.delete(:foreign_type) || "#{poly_type}_type"
          options[:conditions] ||= {}
          if options[:conditions].is_a?(Array)
            cond = options[:conditions].first
            options[:conditions][0] = "(#{cond}) AND #{foreign_type}=#{klass_mapping.to_i}"
          else
            options[:conditions].merge!({foreign_type => klass_mapping.to_i})
          end
        end
      end

      def has_many(name, options = {}, &extension)
        remove_type_and_establish_mapping(name, options)
        super(name, options, &extension)
      end

      def has_one(name, options = {})
        remove_type_and_establish_mapping(name, options)
        super(name, options)
      end
    end

    def self.included(base)
      base.instance_eval {
        def _polymorphic_foreign_types
          @_polymorphic_foreign_types
        end

        def _polymorphic_foreign_types=(types)
          @_polymorphic_foreign_types = types
        end

        self._polymorphic_foreign_types = []
      }
      base.class_eval {
        def _polymorphic_foreign_types
          @_polymorphic_foreign_types
        end

        def _polymorphic_foreign_types=(types)
          @_polymorphic_foreign_types = types
        end

        self._polymorphic_foreign_types = []
      }
      base.extend(ClassMethods)
    end

    def _polymorphic_foreign_types
      self.class._polymorphic_foreign_types
    end

    def [](value)
      if (_polymorphic_foreign_types.include?(value) rescue false)
        send(value)
      else
        super(value)
      end
    end

    def []=(attr_name, value)
      if (_polymorphic_foreign_types.include?(attr_name) rescue false)
        send("#{attr_name}=", value)
      else
        super(attr_name, value)
      end
    end

  end

end
