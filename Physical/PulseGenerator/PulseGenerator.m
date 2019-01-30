classdef (Abstract) PulseGenerator < EventSender
    %PULSEGENERATOR Class for representing a pulse generator (PulseBlaster or PulseStreamer)
    % An abstract class, which knows to handle objects of class
    %   Sequence
    
    properties
        sequence            % Sequence object, to be loaded to the hardware.
        repeats             % int. How many times each sequence is to be repeated.
        sequencePeriodMultiple = 0; % by default. We might need to add some
                                    % blank time @ end of sequence, so all
                                    % of the devices have the same period.
                                    % This value tells us what (if at all)
                                    % is the period of the system.
    end
    
    properties (Access = protected)
        onChannelsBinary = 0;       % Stores in binary the state of each of
                                    % the channels e.g. 11 (= 1 + 2 + 8)
                                    % means that only channels 0, 1 and 3
                                    % are on.
    end
    
    properties (SetAccess = private)
        sequenceInMemory    % logical. Flag for whether obj.sequence is the same as the one in the hardware
        channels = []       % Channel array. Stores registered channels.
    end
    
    properties (Constant, Hidden)
        NAME = 'pulseGenerator'
        NAME_PULSE_BLASTER = 'pulseBlaster'
        NAME_PULSE_STREAMER = 'pulseStreamer'
    end
    
    properties (Abstract, Constant, Hidden)
        % TOTAL_CHANNEL_NUMBER    % int. channels are indexed in the range (1:obj.TOTAL_CHANNEL_NUMBER)
        MAX_REPEATS             % int. Maximum value for obj.repeats
        MAX_PULSES              % int. Maximum number of pulses in acceptable sequences
        MAX_DURATION            % double. Maximum duration of pulse.
        
        AVAILABLE_ADDRESSES     % List of all available physical addresses.
                                % Should be either vector of doubles or cell of char arrays
    end
    
    methods (Access = protected)
        function obj = PulseGenerator
            % Default constructor.
            name = PulseGenerator.NAME;
            obj@EventSender(name);
        end
        
        function initSequence(obj)
            obj.sequence = Sequence;
        end
        
        function uploadSequence(obj)
            validateSequence(obj)
            
            % We might need to add some blank time @ end of sequence, for
            % synchroniztion purposes
%             obj.setSequenceDelays;    % Still not working properly
            
            seq = obj.sequence;
            t = obj.sequencePeriodMultiple;
            remainder = rem(seq.duration, t);       % returns NaN if t==0; returns 0 if duration is multiple of t
            if ~isnan(remainder) && remainder ~= 0  % That is, we need to add a dummy pulse
                p = Pulse(remainder);
                seq.addPulse(p);
            end
            
            obj.sendToHardware;
            obj.sequenceInMemory = true;
        end
        
%         function setSequenceDelays(obj)
%             % Delay channels in Sequence, according to their preset delays.
%             % Algoritm: split sequence, according to delay
%             % Too complicated, for now. Not working.
%             S = obj.sequence;
%             channelNames = S.activeChannelNames;
%             % Get only active channels in sequence
%             [mChannels, channelIndex] = find(channelNames, obj.channels);
%             channelDelays = [mChannels.delay];
%             % Get actual delay
%             minDelay = min(channelDelays);
%             channelDelays = channelDelays - minDelay;
%             % Remove index of minimum/minima, as it does not need delay,
%             % and delay all other channels.
%             channelIndex(channelDelays < eps) = [];   
%             for j = 1:length(channelIndex)
%                 name = channelNames{channelIndex(j)};
%                 times = S.edgeTimes;
%                 newTimes = times + channelDelays(channelIndex(j));
%                 for k = 1:length(newTimes)
%                     [S1, S2] = S.splitByTime(newTimes(k));
%                     
%                     firstPulse = S1.pulses(end);
%                     level = ismember(name, firstPulse.onChannels);
%                     firstPulse.changChannels(name, ~level);
% 
%                     
%                 end
%             end
%             obj.delayChannel(channelNames(channelIndex), channelDelays);
%         end
    end
    
    methods % Setters & getters
        function set.sequence(obj, S)
            % Whenever we change the current sequence, we necessarily have
            % a different sequence than the one on the hardware, until we
            % uploadSequence()
            if ~isa(S, 'Sequence')
                obj.sendError('New sequence must be of class ''Sequence''!')
            end
            obj.sequence = S;
            obj.sequenceInMemory = false; %#ok<MCSUP>
        end
        
        function set.repeats(obj, r)
            % Validating for strictly positive integer
            if ~ValidationHelper.isValuePositiveInteger(r)
                error('Number of repeats must be a positive integer!') 
            elseif (r > obj.MAX_REPEATS)
                error('I can''t keep up with it! Try using less repeats.')
            end
            obj.repeats = r;
        end
        
    end
    
    %% Channel registration and retrieval
    methods
       
        function registerChannel(obj, channels)
            % Supports arrays of Channels
            
            %%% Validation %%%
            % Channel data is in correct format
            if ~isa(channels, 'Channel')
                error('Object to be registered is not a channel! Ignoring.')
            end
            warnMsg = '';
            % Name is not yet taken
            name = {channels.name};
            occupiedName = obj.channelNames;        % list of channel names already taken
            nameValid = ~ismember(name, occupiedName);
            if any(~nameValid)
                warnMsg = [warnMsg, 'Some of the channels could not be registered, since their name already exists in the registrar.'];
            end
            % Physical addresses is available
            address = [channels.address];       % Careful! if channels.address is a char array, this might break!
            addressValid = ismember(address, obj.AVAILABLE_ADDRESSES);
            % & Not taken already
            occupiedAdd = obj.channelAddresses; % List of physical addresses already taken
            addressTaken = ismember(address, occupiedAdd);
            if any(addressTaken)
                % Maybe we are trying to register the same channel again,
                % and that's fine
                ind = find(addressTaken);
                for k = 1:length(ind)
                    pgInd = find(occupiedAdd == address(ind(k)));   % index of channel IN THE PG CHANNEL ARRAY
                    if strcmp(name, occupiedName(pgInd)) %#ok<FNDSB>
                        addressTaken(ind(k)) = false;
                        nameValid(ind(k)) = true;
                    end
                end
            end
            if any(~addressValid || addressTaken)
                warnMsg = [warnMsg, 'Some of the channels could not be registered in specified adresses.\n'];
            end
            % Let user know what's going on
            tf = nameValid && addressValid && ~addressTaken;
            if ~any(tf)
                obj.sendError('No channel was registered.')
            elseif any(~tf)
                obj.sendWarning(warnMsg);
            end
            
            %%% Registration %%%
            % Valid channels are added to channel array
            obj.channels = [obj.channels, channels(tf)];

        end
        
        function tf = isOn(obj, channelName)
            address = obj.channelName2Address(channelName);
            ind = address + 1;  % Addresses start at 0, but MATLAB vectors start at 1
            tf = bitget(obj.onChannelsBinary, ind);
        end
        
        function names = channelNames(obj)
            if isempty(obj.channels)
                names = {};
                return
            end
            names = {obj.channels.name};
        end
        
        function addresses = channelAddresses(obj)
            %{
            format = class(obj.AVAILABLE_ADDRESSES);
            switch format
                case {'int', 'double'}
            %}
            if isempty(obj.channels)
                addresses = [];
                return
            end
            addresses = [obj.channels.address];
            %{
                case 'cell'
                    if isempty(obj.channels)
                        addresses = {};
                        return
                    end
                    addresses = {obj.channels.address};
                otherwise
                    error('Unknown address type!')
            end
            %}
        end
    end
       
    methods (Access = protected)
        function address = channelName2Address(obj, name)
            % Supports cell arrays of 'name'
            if iscell(name)
                % find for each name seperately
                len = length(name);
                address = -ones(0, len);
                for i = 1:len
                    index = find(strcmp(name{i}, obj.channelNames));
                    if ~isempty(index)
                        address(i) = obj.channels(index).address;
                    end
                end
                invalidNum = sum(address < 0);
                if invalidNum ~= 0
                    msg = sprintf('%d channels could not be found', invalidNum);
                    obj.sendWarning(msg);
                end
            else
                % simpler case: only one name
                index = find(strcmp(name, obj.channelNames)); % Should return the index of the channel in obj.channels
                if isempty(index)
                    obj.sendWarning('Could not find requested channel!');
                    address = -1;
                else
                    address = obj.channels(index).address;
                end
            end
        end
    end
       
    methods % Should be protected, but isn't for now, because of how delays are implemented
        function [onDelay, offDelay] = channelName2Delays(obj, name)
            % Name must be single char array ("string")
            index = find(strcmp(name, obj.channelNames)); % Should return the index of the channel in obj.channels
            if isempty(index)
                obj.sendWarning('Could not find requested channel!');
                onDelay = -1;
                offDelay = -1;
            else
                chan = obj.channels(index);
                onDelay = chan.onDelay;
                offDelay = chan.offDelay;
            end
        end
        
    end
    
    %% Wrapper methods
    methods (Abstract)
%         Initialize(obj) ????
        % Loads dll's. Maybe also create default sequence
        
        on(obj, channel)
        %   obj.pulseGeneratorPrivate.On(channel);
        
        off(obj)
        %   obj.pulseGeneratorPrivate.Off;
        
        run(obj)
        % Upload sequence to hardware (if needed) and actually start it
        
        validateSequence(obj)
        % Needs to run before uploading it to PG hardware
        
        sendToHardware(obj)
        % After all validation is done - upload the sequence to PG hardware

    end
    
    %%
    methods (Static)
        function obj = create(struct)
            type = PulseGenerator.generatorType(struct);
            switch type
                case 'dummy'
                    obj = PulseGeneratorDummyClass.GetInstance(struct);
                case PulseGenerator.NAME_PULSE_BLASTER
                    obj = PulseBlasterNewClass.GetInstance(struct);
                case PulseGenerator.NAME_PULSE_STREAMER
                    obj = PulseStreamerNewClass.getInstance(struct);
                otherwise
                    EventStation.anonymousWarning('Could not create Pulse Generator of type %s!', type)
            end
        end
        
        function type = generatorType(struct)
            % type - string. Type of pulse generator. For now, either
            % 'pulseBlaster' or 'pulseStreamer'
            if ~isfield(struct, 'type')
                type = PulseGenerator.NAME_PULSE_BLASTER;
            else
                type = struct.type;
            end
        end
    end
end