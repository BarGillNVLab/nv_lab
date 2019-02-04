classdef FrequencyGeneratorWindfreak < FrequencyGenerator & SerialControlled
    %FREQUENCYGENERATORWINDFREAK Windfreak frequency generator class
    % includes, for now, synthHD & synthNV
    
    properties (Constant, Hidden)
        MIN_FREQ = 0;                   % Hz
        LIMITS_AMPLITUDE = [-60, 18];   % dB. These values may not be reached, depending on the output type.
        
        TYPE = {'synthhd', 'synthnv'};
        
        NEEDED_FIELDS = {'address', 'serialNumber'}
    end
    
    methods (Access = private)
        function obj=FrequencyGeneratorWindfreak(name, address)
            obj@FrequencyGenerator(name);
            obj@SerialControlled(address);
            
            obj.initialize;
        end
    end
    
    properties (SetAccess = protected)
        maxFreq = 4.05e9;
    end
    
    methods
        function varargout = sendCommand(obj, what, value)
            % value - sent value or ?. units can also be added to value
            varargout={0};
            %%% set the command to be sent to the SRS
            command = createCommand(obj, what, value);
            
            fopen(obj.address);
            try
                %fprintf(obj.address,C1r1);
                fprintf(obj.address, command);
                % Get the output - if needed
                if strcmp(value, '?')
                    varargout = {fscanf(obj.address,'%s')};
                end
            catch err
                fclose(obj.address);
                rethrow(err)
            end
            fclose(obj.address);
            
        end
        
        %        function [pdB] = PowerSynthHDtodB(obj,pSynthHD)
        %
        %            if pSynthHD>24000
        %                pdB=((pSynthHD-26100)/(2.1e-11))^0.084531;
        %            else
        %                pdB=(pSynthHD-21520)/233.4;
        %            end
        %
        %        end
        %        function [pSynthHD] = PowerdBtoSynthHD(obj,pdB)
        %            if (pdB<-60)
        %                pdB = -60;
        %            end
        %            if (pdB>18)
        %                pdB = 18;
        %            end
        %
        %            if pdB>10
        %                pSynthHD=round(2.101e-11*pdB^(11.83)+26110);
        %            else
        %                pSynthHD=round(233.4*pdB+21520);
        %            end
        %
        %        end
        
    end
    
    methods (Static)
        function obj = getInstance(struct)
            type = struct.type;     % We already know it exists
            
            missingField = FactoryHelper.usualChecks(struct, ...
                FrequencyGeneratorSRS.NEEDED_FIELDS);
            if ~isnan(missingField)
                EventStation.anonymousError(...
                    'Trying to create a %s frequency generator, encountered missing field - "%s". Aborting',...
                    type, missingField);
            end
            
            name = [lower(type), 'FrequencyGenerator', '-', struct.serialNumber];
            obj = FrequencyGeneratorSRS(name, struct.address);
            addBaseObject(obj);
        end
        
        function command = createCommand(what, value)
            switch lower(what)
                case {'channel', 'chan'}
                    name = 'C';
                case {'enableoutput', 'output', 'enable'}
                    name='r';
                case {'frequency', 'freq', 'f'}
                    name='f';
                    if ~strcmp(value, '?') % convert sent values if needed
                        value = str2double(value)/1e6;             %%% convert Hz to MHz (SynthHD uses MHz)
                    end
                case {'amplitude', 'ampl', 'a'}
                    name='W';
                    %    value=num2str(obj.PowerdBtoSynthHD(str2double(value)));  %%% convert dbm to strange units of the SynthHD
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

