classdef (Abstract) FrequencyGenerator < BaseObject
    %FREQUENCYGENERATOR Abstract class for frequency generators
    % Has 3 public (and Dependent) properties:
    % # output (On/Off),
    % # frequency (in Hz) and
    % # amplitude (in dB)
    %
    % Subclasses need to:
    % 1. specify values for the constants:
    %       MIN_FREQ
    %       LIMITS_AMPLITUDE
    % 2. implement the functions:
    %       varargout = sendCommand(obj, command, value)
    %       value = readOutput(obj)
    %       (Static) newFG = getInstance(struct)
    %       (Static) command = createCommand(what, value)
    % 3. call obj.initialize by the end of the constructor
    
    
    properties (Dependent)
        frequency   % Hz
        amplitude   % dB
        output      % logical. On/off
    end
    
    properties (Abstract, Constant)
        % Minimum and maximum values
        MIN_FREQ            % for MW frequency
        LIMITS_AMPLITUDE    % for MW amplitude
        
        TYPE    % for now, one of: {'srs', 'synthhd', 'synthnv'}
    end
    
    properties (Constant, Access = private)
        NEEDED_FIELDS = {'address'}
    end
    
    properties (Access = private)
        % Store values internally, to reduce time spent over serial connection
        frequencyPrivate    % double
        amplitudePrivate    % double.
        outputPrivate       % logical. Output on or off;
    end
    
    properties (Abstract, SetAccess = protected)
        maxFreq
    end
    
    methods (Access = protected)
        function obj = FrequencyGenerator(name)
            obj@BaseObject(name);
        end
        
        function initialize(obj)
            obj.connect;
            obj.frequencyPrivate = obj.queryValue('frequency');
            obj.amplitudePrivate = obj.queryValue('amplitude');
            obj.outputPrivate    = obj.queryValue('enableOutput');
            obj.disconnect;
        end
    end
    
    methods
        function frequency = get.frequency(obj)
            frequency = obj.frequencyPrivate;
        end
        function amplitude = get.amplitude(obj)
            amplitude = obj.amplitudePrivate;
        end
        function output = get.output(obj)
            output = obj.outputPrivate;
        end
        
        function set.output(obj, value)
            switch value
                case {'1', 1, 'on', true}
                    obj.setValue('enableOutput', '1')
                    obj.outputPrivate = true;
                case {'0', 0, 'off', false}
                    obj.setValue('enableOutput', '0')
                    obj.outputPrivate = false;
                otherwise
                    error('Unknown command. Ignoring')
            end
        end
        
        function set.amplitude(obj, newAmplitude)  % in dB
            % Change amplitude level of the frequency generator
            if ~ValidationHelper.isInBorders(newAmplitude, obj.LIMITS_AMPLITUDE(1), obj.LIMITS_AMPLITUDE(2))
                error('MW amplitude must be between %d and %d.\nRequested: %d', ...
                    obj.LIMITS_AMPLITUDE(1), obj.LIMITS_AMPLITUDE(2), newAmplitude)
            end
            
            switch length(newAmplitude)
                case 1
                    obj.setValue('amplitude', newAmplitude);
                    obj.amplitudePrivate(1) = newAmplitude;
                case length(obj.amplitudePrivate)
                    obj.setValue('amplitude', newAmplitude);
                    obj.amplitudePrivate = newAmplitude;
                otherwise
                    EventStation.anonymousError('Frequency Generator: amplitude vector size mismatch!');
            end
            
            
        end
        
        function set.frequency(obj, newFrequency)      % in Hz
            % Change frequency level of the frequency generator
            if ~ValidationHelper.isInBorders(newFrequency, obj.MIN_FREQ, obj.maxFreq)
                error('MW frequency must be between %d and %d.\nRequested: %d', ...
                    obj.MIN_FREQ, obj.maxFreq, newFrequency)
            end
            
            switch length(newFrequency)
                case 1
                    obj.setValue('frequency', newFrequency);
                    obj.frequencyPrivate(1) = newFrequency;
                case length(obj.frequencyPrivate)
                    obj.setValue('frequency', newFrequency);
                    obj.frequencyPrivate = newFrequency;
                otherwise
                    EventStation.anonymousError('Frequency Generator: frequency vector size mismatch!');
            end
        end
        
        
        function value = queryValue(obj, what)
            command = obj.createCommand(what, '?');
            sendCommand(obj, command);
            value = str2double(obj.readOutput);
        end
        
        function setValue(obj, what, value)
            % Can be overridden by children
            command = obj.createCommand(what, value);
            sendCommand(obj, command);
        end
    end
    
    methods (Abstract)
        sendCommand(obj, command)
        % Actually sends command to hardware
        
        value = readOutput(obj)
        % Get value returned from object

        connect(obj)
        % Starts connection with FG (might be empty)

        disconnect(obj)
        % Closes connection with FG (might be empty)
    end
    
    methods (Abstract, Static)
        obj = getInstance(struct)
        % So that the constructor remains private
        
        command = createCommand(obj, what, value)
        % Converts request type and value to a command that can be sent to Hardware.
    end
    
    %% Initializtion and Setup
    methods (Static)
        function freqGens = getFG()
            % Returns an instance of cell{all FG's}
            %
            % The cell is ordered, so that the first one is the default FG
            
            persistent fgCellContainer
            if isempty(fgCellContainer) || ~isvalid(fgCellContainer)
                FGjson = JsonInfoReader.getJson.frequencyGenerators;
                fgCellContainer = CellContainer;
                isDefault = false(size(FGjson));    % initialize
                
                for i = 1: length(FGjson)
                    %%% Checks on each individual struct %%%
                    if iscell(FGjson); curFgStruct = FGjson{i}; ...
                        else; curFgStruct = FGjson(i); end
                    
                    % If there is no type, then it is a dummy
                    if isfield(curFgStruct, 'type'); type = curFgStruct.type; ...
                        else; type = FrequencyGeneratorDummy.TYPE; end
                    
                    % Usual checks on fields
                    missingField = FactoryHelper.usualChecks(curFgStruct, ...
                        FrequencyGenerator.NEEDED_FIELDS);
                    if ischar(missingField) && ~any(isnan(missingField)) && ...  Some field is missing
                            ~strcmp(type, FrequencyGeneratorDummy.TYPE) % This FG is not dummy
                        EventStation.anonymousError(...
                            'Trying to create a %s frequency generator, encountered missing field - "%s". Aborting',...
                            type, missingField);
                    end
                    
                    % Check whether this is THE default FG
                    if isfield(curFgStruct, 'default'); isDefault(i) = true; end
            
                    %%% Get instance (create, if one doesn't exist) %%%
                    t = lower(type);
                    switch t
                        case FrequencyGeneratorSRS.TYPE
                            try
                                newFG = getObjByName(FrequencyGeneratorSRS.NAME);
                            catch
                                newFG = FrequencyGeneratorSRS.getInstance(curFgStruct);
                            end
                        case FrequencyGeneratorWindfreak.TYPE
                            try
                                name = [t, 'FrequencyGenerator'];
                                newFG = getObjByName(name);
                            catch
                                newFG = FrequencyGeneratorWindfreak.getInstance(curFgStruct);
                            end
                        case FrequencyGeneratorDummy.TYPE
                            newFG = FrequencyGeneratorDummy.getInstance(curFgStruct);
                        otherwise
                            EventStation.anonymousWarning('Could not create Frequency Generator of type %s!', type)
                    end
                    fgCellContainer.cells{end + 1} = newFG;
                end
                
                nDefault = sum(isDefault);
                switch nDefault
                    case 0
                        % Nothing.
                    case 1
                        % We move the default one to index 1
                        ind = 1:find(isDefault);
                        indNew = circshift(ind, 1); % = [ind, 1, 2, ..., ind-1]
                        fgCellContainer.cells{ind} = fgCellContainer.cells{indNew};
                    otherwise
                        EventStation.anonymousError('Too many Frequency Generators were set as default! Aborting.')
                end
                
            end
            
            freqGens = fgCellContainer.cells;
        end
        
        function num = nAvailable
            num = length(FrequencyGenerator.getFG);
        end
        
        function name = getDefaultFgName()
            fgCells = FrequencyGenerator.getFG;
            if isempty(fgCells)
                EventStation.anonymousError('There is no active frequency generator!')
            end
            fg = fgCells{1};   % We sorted the array so that the default FG is first
            name = fg.name;
        end

    end
    
end

