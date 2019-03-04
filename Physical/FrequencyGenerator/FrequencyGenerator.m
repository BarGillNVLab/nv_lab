classdef (Abstract) FrequencyGenerator < BaseObject
    %FREQUENCYGENERATOR Abstract class for frequency generators
    % Has 3 public (and Dependent) properties:
    % # output (On/Off),
    % # frequency (in Hz) and
    % # amplitude (in dB)
    %
    % Subclasses need to:
    % 1. implement the functions:
    %       varargout = sendCommand(obj, command, value)
    %       value = readOutput(obj)
    %       (Static) newFG = getInstance(struct)
    %       (Static) command = createCommand(what, value)
    % 2. call obj.initialize by the end of the constructor
    
    
    properties (Dependent)
        frequency   % Hz
        amplitude   % dB
        output      % logical. On/off
    end
    
    properties (Abstract, Constant)
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
    
    properties (SetAccess = protected)
        minFreq
        maxFreq
        minAmpl
        maxAmpl
    end
    
    methods (Access = protected)
        function obj = FrequencyGenerator(name, freqLimits, amplLimits)
            obj@BaseObject(name);
            
            obj.minFreq = freqLimits(1);
            obj.maxFreq = freqLimits(2);
            obj.minAmpl = amplLimits(1);
            obj.maxAmpl = amplLimits(2);
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
            if ~ValidationHelper.isInBorders(newAmplitude, obj.minAmpl, obj.maxAmpl)
                error('MW amplitude must be between %d and %d.\nRequested: %d', ...
                    obj.minAmpl, obj.maxAmpl, newAmplitude)
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
            if ~ValidationHelper.isInBorders(newFrequency, obj.minFreq, obj.maxFreq)
                error('MW frequency must be between %d and %d.\nRequested: %d', ...
                    obj.minFreq, obj.maxFreq, newFrequency)
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
                            newFG = getObjByName(FrequencyGeneratorSRS.NAME);
                            if isempty(newFG)
                                newFG = FrequencyGeneratorSRS.getInstance(curFgStruct);
                            end
                        case FrequencyGeneratorWindfreak.TYPE
                            name = [t, 'FrequencyGenerator'];
                            newFG = getObjByName(name);
                            if isempty(newFG)
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

