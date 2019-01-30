classdef MW
    %MWGATE 
    
    properties (Constant)
        NEEDED_FIELDS = {'MW'};
        OPTIONAL_FIELDS = {'I', 'Q'};
        OPTIONAL_FIELDS2 = {'IQ2'};
    end
    
    methods (Static)
        function create(mwStruct)
            %%% Part 1: creating switches 
            % Every Setup has to have a MW switch
            nFields = MW.NEEDED_FIELDS;
            missingField = FactoryHelper.usualChecks(mwStruct, nFields);
            if ~isnan(missingField)
                EventStation.anonymousError(...
                    'Can''t initialize Microwave - needed field "%s" was not found in initialization struct!', ...
                    missingField);
            end
            
            % Some setups have I & Q switches, as well
            if isnan(FactoryHelper.usualChecks(struct, MW.OPTIONAL_FIELDS))
                % usualChecks() returning nan means these fileds exist
                nFields = [nFields, MW.OPTIONAL_FIELDS];
            end
            
            % Actually creating the switches
            for j = 1:length(nFields)
                S = mwStruct.(nFields{j});
                
                switch lower(S.classname)
                    case {'pulsegenerator', 'pulsestreamer', 'pulseblaster'}
                        SwitchPgControlled.create(S.switchChannelName, S);
                    otherwise
                        EventStation.anonymousError(...
                            'Can''t create a %s-class fast switch - unknown classname! Aborting.', ...
                            S.classname);
                end
            end
            
            %%% Part 2: Creating an IQ2, if needed
            if isnan(FactoryHelper.usualChecks(struct, MW.OPTIONAL_FIELDS2))
                IQ2Struct = struct.IQ2;
                switch lower(IQ2Struct.classname)
                    case 'nidaq'
                        IQSwitchNidaqControlled.create(IQ2Struct);
                    otherwise
                        EventStation.anonymousError(...
                            'Can''t create a %s-class IQ2 - unknown classname! Aborting.', ...
                            S.classname);
                end
            end
        end
    end
    
end

