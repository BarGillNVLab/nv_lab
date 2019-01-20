classdef Tracker < EventSender & EventListener & Savable
    %TRACKER In charge of all trackables (tracking experiments)
    
    properties (Constant)
        NAME = 'Tracker'
        EVENT_TRACKER_FINISHED = 'trackerFinished'

        REFERENCE_TYPE_KCPS = 'kcpsReference'
        
        THRESHHOLD_FRACTION = 0.01;  % Change is significant if dx/x > threshhold fraction (Default)
    end
     
    properties (Access = private)
        mLocalStruct = struct;
        
        kcpsReference = [];  % Initialize as 0
    end
    
    properties
        kcpsThreshholdFraction = Tracker.THRESHHOLD_FRACTION;   % Default value
    end
    
    methods
        function sendEventTrackerFinished(obj)
            obj.sendEvent(struct(obj.EVENT_TRACKER_FINISHED,true));
        end
        
        function obj = Tracker
            obj@Savable(Tracker.NAME);
            obj@EventSender(Tracker.NAME);
            obj@EventListener();
            
            obj.startListeningTo(obj.getTrackableExperiments);
        end
    end
    
    methods
        function compareReference(obj, newValue, referenceType, trackableName)
            % Compares newValue to reference of type referenceType, using
            % trackable.
            
            switch referenceType
                case obj.REFERENCE_TYPE_KCPS
                    reference = obj.kcpsReference;
                    threshhold = obj.kcpsThreshholdFraction;
                    refName = ' kcps';
                otherwise
                    EventStation.anonymousError('This Shouldn''t have happenned!')
            end
            
            if isempty(reference)
                obj.kcpsReference = newValue;
                fprintf('Setting tracker reference as %.2f%s\n', newValue, refName);
            elseif obj.isDifferenceAboveThreshhold(newValue, reference, threshhold)
                obj.kcpsReference = newValue;
                fprintf('Tracking reference jumped, setting value to %.2f%s\n', newValue);
            elseif obj.isDifferenceAboveThreshhold(reference, newValue, threshhold)
                fprintf('Starting tracking, current counts are %.2f%s, reference is %.2f%s\n', ...
                    newValue, refName, reference, refName);
                trackable = obj.getTrackable(trackableName);
                trackable.startTrack;
            end
        end
    end
    
    methods % Setters
        function set.kcpsThreshholdFraction(obj, newFraction)
            if ~ValidationHelper.isValueFraction(newFraction)
                obj.sendError('Fraction must be a numeric value between 0 and 1');
            end
            obj.kcpsThreshholdFraction = newFraction;
        end
    end
    
    methods (Static)
        function init
            newTracker = Tracker;
            replaceBaseObject(newTracker);  % in base object map
        end
    end
    
    %% overriding from Savable
    methods (Access = protected)
        function outStruct = saveStateAsStruct(obj, category, type)
            % Saves the state as struct. if you want to save stuff, make
            % (outStruct = struct;) and put stuff inside. If you dont
            % want to save, make (outStruct = NaN;)
            %
            % category - string. Some objects saves themself only with
            %                    specific category (image/experiments/etc.)
            % type - string.     Whether the objects saves at the beginning
            %                    of the run (parameter) or at its end (result)
            outStruct = NaN;
            
            if ~strcmp(category, obj.CATEGORY_TRACKER)
                return
            end
            
            switch type
                case Savable.TYPE_PARAMS
                    % do nothing, for now
                case Savable.TYPE_RESULTS
                    outStruct = obj.mLocalStruct;
            end
        end
   
        function loadStateFromStruct(obj, savedStruct, category, subCategory) %#ok<INUSD>
            % Loads the state from a struct.
            % To support older versoins, always check for a value in the
            % struct before using it; see example in the first line.
            %
            % category - string. Some savable objects will load stuff
            %            only for the 'image_lasers' category and not for
            %            'image_stages' category, for example
            % subCategory - string. Might be an empty string
   
            if isfield(savedStruct, 'some_value')
                obj.my_value = savedStruct.some_value;
            end
        end
    
        function string = returnReadableString(obj, savedStruct) %#ok<INUSD>
            % return a readable string to be shown. if this object
            % doesn't need a readable string, make (string = NaN;) or
            % (string = '');
    
            string = NaN;
        end
    end
    
    methods (Static)
        function categoryName = mCategory
            categoryName = Savable.CATEGORY_TRACKER;
        end
    end
    
    %% overridden from EventListener
    methods
        % When events happen, this function jumps.
        % event is the event sent from the EventSender
        function onEvent(obj, event)
            if isfield(event.extraInfo, Trackable.EVENT_TRACKABLE_EXP_ENDED)
                % Two actions:
                %   1. Saves trackable history into the tracker history.
                %   2. Sends an event that this trackable finished, and now
                %      things should happen (Main experiment can be
                %      resumed, SavLoad will autosave, etc.)
                trackable = event.creator;
                trackableName = trackable.name;     % trackable.name (lowercase) == 'trackableX', where X is the tracked property
                obj.mLocalStruct.(trackableName) = trackable.convertHistoryToStructToSave;
                
                % Update relevant reference value (kcps, etc.)
                switch trackableName
                    case TrackablePosition.NAME
                        endRecord = trackable.mHistory{end};
                        newValue = endRecord.value;
                        obj.kcpsReference = newValue;
                        fprintf('Tracking ended, setting tracker reference as %.2f kcps\n', newValue);
                    otherwise
                        disp('This should not have happenned')
                end
                obj.sendEventTrackerFinished;
            end
        end
    end
    
    %% Statics
    methods (Static)
        function namesCell = getTrackableExperiments %% for now, it is that simple
            % To be implemented
            % TRACKABLE_POWER_NAME = 'trackablePower';
            % TRACKABLE_FREQUENCY_NAME = 'trackableFrequency';
            % TRACKABLE_MAGNETIC_NAME = 'trackableMagnetic';
            %
            % They will be programatically found (using something similar
            % to Experiment.getExperimentNames()
            namesCell = TrackablePosition.NAME;
        end
        
        function trackable = getTrackable(trackableName, varargin)
            try
                % Maybe this trackable already exists
                trackable = getObjByName(trackableName);
            catch
                switch trackableName
                    case TrackablePosition.NAME
                        % If this is the case, calling the function might
                        % have included stage name
                        if ~isempty(varargin)
                            stageName = varargin{1};
                            trackable = TrackablePosition(stageName);
                        else
                            % Default stage is invoked
                            trackable = TrackablePosition;
                        end
                    otherwise
                        disp('This should not have happenned')
                end
            end
        end
        
        function tf = isDifferenceAboveThreshhold(maybeHigh, maybeLow, threshhold)
            tf = (maybeHigh - maybeLow) > threshhold;
        end
    end
    
end

