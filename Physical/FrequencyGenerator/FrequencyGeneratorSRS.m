classdef FrequencyGeneratorSRS < FrequencyGenerator
    %FREQUENCYGENERATORSRS SRS frequency genarator class
    
    properties (Constant, Hidden)
        MIN_FREQ = 0;  % Hz
        LIMITS_AMPLITUDE = [-100, 10];   % dB. These values may not be reached, depending on the output type.
        
        TYPE = 'srs';
        NAME = 'srsFrequencyGenerator';
        
        NEEDED_FIELDS = {'port', 'serialNumber', 'minFrequency', 'maxFrequency', 'minAmplitude', 'maxAmplitude'}
    end
       
    properties (Access = private)
        t       % tcpip object
    end
    
    methods (Access = private)
        function obj = FrequencyGeneratorSRS(name, address, port, frequencyLimits, amplitudeLimits)
            % All models are the same in regards to controlling them, but
            % the limitations on the amplitude and on the allowed frequencies may vary.
            obj@FrequencyGenerator(name, frequencyLimits, amplitudeLimits);
            obj.t = tcpip(address, port);
            
            obj.initialize;
        end
    end
       
    methods
        function connect(obj)
            if strcmp(obj.t.Status, 'closed')
                fopen(obj.t);
            end
        end

        function disconnect(obj)
            if strcmp(obj.t.Status, 'open')
                fclose(obj.t);
            end
        end

        function delete(obj)
            obj.disconnect;
            delete(obj.t)
        end
    end
   
    %%
    methods
        function sendCommand(obj, command)
            % Actually sends command to hardware
            obj.connect;
            fprintf(obj.t, command);
            obj.disconnect;
        end
        
        function value = readOutput(obj)
            % Get value returned from object
            obj.connect;
            value = fscanf(obj.t, '%s');
            obj.disconnect;
        end
    end
    
    %%
    methods (Static)
        function obj = getInstance(struct)
            missingField = FactoryHelper.usualChecks(struct, ...
                FrequencyGeneratorSRS.NEEDED_FIELDS);
            if ~isnan(missingField)
                EventStation.anonymousError(...
                    'Trying to create an SRS frequency generator, encountered missing field - "%s". Aborting',...
                    missingField);
            end
            
            name = [FrequencyGeneratorSRS.NAME, '-', struct.serialNumber];
            frequencyLimits = [struct.minFrequency, struct.maxFrequency];
            amplitudeLimits = [struct.minAmplitude, struct.maxAmplitude];
            obj = FrequencyGeneratorSRS(name, struct.address, struct.port, frequencyLimits, amplitudeLimits);

            addBaseObject(obj);
        end
        
        function command = createCommand(what, value)
           switch lower(what)
               case {'enableoutput', 'output', 'enabled', 'enable'}
                   name = 'ENBR';
               case {'frequency', 'freq'}
                   name = 'FREQ';
                   if ~strcmp(value, '?') % convert sent values if needed
                       value = value*1e6;
                   end
               case {'amplitude', 'ampl', 'amp'}
                   name = 'AMPR';
               otherwise
                   error('Unknown command type %s', what)
           end
           
           if isnumeric(value)
               value = num2str(value);
           end
           command = [name, value];
       end
    end

end

