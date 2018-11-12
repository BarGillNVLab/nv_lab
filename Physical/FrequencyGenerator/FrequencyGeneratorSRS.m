classdef FrequencyGeneratorSRS < FrequencyGenerator
    %FREQUENCYGENERATORSRS SRS frequency genarator class
    
    properties (Constant, Hidden)
        MIN_FREQ = 0;  % Hz
        LIMITS_AMPLITUDE = [-100, 10];   % dB. These values may not be reached, depending on the output type.
        
        TYPE = 'srs';
        NAME = 'srsFrequencyGenerator';
        
        NEEDED_FIELDS = {'port', 'serialNumber', 'maxFrequency'}
    end
    
    properties (SetAccess = protected)
        maxFreq
    end
       
    properties (Access = private)
        t       % tcpip object
    end
    
    methods (Access = private)
        function obj = FrequencyGeneratorSRS(name, address, port, maxFrequency)
            % All models are the same in regards to controlling them, but
            % some can generator higher frequencies; this is therefore a
            % parameter of the constructor.
            obj@FrequencyGenerator(name);
            obj.t = tcpip(address, port);
            fopen(obj.t);
            
            obj.maxFreq = maxFrequency;
            
            obj.initialize;
        end
        
        function delete(obj)
            fclose(obj.t);
            delete(obj.t)
        end
    end
   
    %%
    methods
        function sendCommand(obj, command)
            % Actually sends command to hardware
            fprintf(obj.t, command);
        end
        
        function value = readOutput(obj)
            % Get value returned from object
            value = fscanf(obj.t, '%s');
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
            obj = FrequencyGeneratorSRS(name, struct.address, struct.port, struct.maxFrequency);
            addBaseObject(obj);
        end
        
        function command = nameToCommandName(name)
           switch lower(name)
               case {'enableoutput', 'output', 'enabled', 'enable'}
                   command = 'ENBR';
               case {'frequency', 'freq'}
                   command = 'FREQ';
               case {'amplitude', 'ampl', 'amp'}
                   command = 'AMPR';
               otherwise
                   error('Unknown command type %s', name)
           end         
       end
    end

end

