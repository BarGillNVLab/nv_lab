classdef (Sealed) FrequencyGeneratorDummy < FrequencyGenerator
    %FREQUENCYGENERATORDUMMY Summary of this class goes here
    %   Detailed explanation goes here
    
    properties (Constant, Hidden)
        MIN_FREQ = 0;                   %Hz
        LIMITS_AMPLITUDE = [-100, 10];  %dB
        
        TYPE = 'dummy'
        
        NEEDED_FIELDS = {'name'}
    end
    
    properties (SetAccess = protected)
        maxFreq = 4.05e9;
    end
    
    methods (Access = private)
        function obj = FrequencyGeneratorDummy(name)
            obj@FrequencyGenerator(name);
            
            obj.initialize;
        end
    end
    
    methods
        function sendCommand(obj, command) %#ok<*INUSD>
            % No need to do anything
        end
        
        function value = readOutput(obj) %#ok<*MANU>
            % We explicitly request value from the device. Let's say it's
            % 0, as long as dummy is involved.
            value = '0';
        end
    end
    
    methods (Static)
        function obj = getInstance(struct)
            
            missingField = FactoryHelper.usualChecks(struct, ...
                FrequencyGeneratorDummy.NEEDED_FIELDS);
            if ~isnan(missingField)
                EventStation.anonymousError(...
                    'Trying to create a dummy frequency generator, encountered missing field - "%s". Aborting',...
                    missingField);
            end
            
            obj = FrequencyGeneratorDummy(struct.name);
            addBaseObject(obj);
            
        end
        
        function command = nameToCommandName(name)
            switch lower(name)
               case {'enableoutput', 'output', 'enabled', 'enable'}
                   command = 'output';
               case {'frequency', 'freq'}
                   command = 'frquency';
               case {'amplitude', 'ampl', 'amp'}
                   command = 'amplitude';
               otherwise
                   error('Unknown command type: ''%s''',name)
           end    
        end
    end
    
end

