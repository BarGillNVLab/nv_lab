classdef Experiment < EventSender & EventListener & Savable
    %EXPERIMENT Summary of this class goes here
    %   Detailed explanation goes here
    
    
    properties
        mCurrentAxisXParam      % stores the ExpParameter that is in charge of axis x (which has name and value)
        mCurrentAxisYParam		% stores the ExpParameter that is in charge of axis y (which has name and value) 

    end
    
    properties(Constant = true)
        NAME = 'Experiment'
        
        EVENT_PLOT_UPDATED = 'plotUpdated' % when something changed regarding the plot (new data, change in x\y axis, change in x\y labels)
        EVENT_EXP_RESUMED = 'experimentResumed' % when the experiment is starting to run
        EVENT_EXP_PAUSED = 'experimentPaused' % when the experiment stops from running
        EVENT_PLOT_ANALYZE_FIT = 'plot_analyzie_fit' % when the experiment wants the plot to draw the fitting-function-analysis
        EVENT_PARAM_CHANGED = 'experimentParameterChanged' % when one of the sequence params \ general params is changed
    end
    
    methods
        function sendEventPlotUpdated(obj); obj.sendEvent(struct(obj.EVENT_PLOT_UPDATED, true)); end
        function sendEventExpResumed(obj); obj.sendEvent(struct(obj.EVENT_EXP_RESUMED, true)); end
        function sendEventExpPaused(obj); obj.sendEvent(struct(obj.EVENT_EXP_PAUSED, true)); end
        function sendEventPlotAnalyzeFit(obj); obj.sendEvent(struct(obj.EVENT_PLOT_ANALYZE_FIT, true)); end
        function sendEventParamChanged(obj); obj.sendEvent(struct(obj.EVENT_PARAM_CHANGED, true)); end
        
        
        function obj = Experiment()
            obj@EventSender(Experiment.NAME);
            obj@Savable(Experiment.NAME);
            obj@EventListener(Tracker.NAME);
            obj.mCurrentAxisXParam = ExpParameter.createDefault(ExpParameter.TYPE_VECTOR_OF_DOUBLES, 'axis x', [], obj);
            obj.mCurrentAxisXParam = ExpParameter.createDefault(ExpParameter.TYPE_VECTOR_OF_DOUBLES, 'axis y', [], obj);
            
            % copy parameters from previous experiment
            prevExp = removeObjIfExists(Experiment.NAME);
            if isa(prevExp, 'Experiment'); obj.robAndKillPrevExperiment(prevExp); 
            else; EventStation.anonymousWarning('can''t find previous experiment, initiating parameters from scratch...');
            end
            
            addBaseObject(obj);
        end
        
        function cellOfStrings = getAllExpParameterProperties(obj)
            % get all the property-names of properties from the
            % "Experiment" obj that are from type "ExpParameter"
            allMaybeProperties = obj.getAllNonConstProperties();
            allExpParamProp = cellfun(@(x) isa(obj.(x), 'ExpParameter'), allMaybeProperties);
            cellOfStrings = allMaybeProperties(allExpParamProp);
        end
        
        function robAndKillPrevExperiment(obj, prevExperiment)
            % get all the "ExpParameter"s from the previous experiment
            % prevExperiment = the previous experiment
            
            for paramNameCell = prevExperiment.getAllExpParameterProperties()
                paramName = paramNameCell{:};
                if isprop(obj, paramName)
                    % if the current experiment has this property also
                    obj.(paramName) = prevExperiment.(paramName);
                    obj.(paramName).exp = obj;  % let the expParam look at its new experiment!
                end
            end
            removeBaseObject(prevExperiment);
            delete(prevExperiment);
            
        end
        
        function delete(obj)
            % todo needed? 
        end
    end
    
    
    %% overridden from EventListener
    methods
        % when event happen, this function jumps.
        % event is the event sent from the EventSender
        function onEvent(obj, event)
            if isfield(event.extraInfo, Tracker.EVENT_TRACKER_FINISHED)
                % todo - stuff
            end
        end
    end
    
    
    %% overriding from Savable
    methods(Access = protected)
        function outStruct = saveStateAsStruct(obj, category) %#ok<*MANU>
            % saves the state as struct. if you want to save stuff, make
            % (outStruct = struct;) and put stuff inside. if you dont
            % want to save, make (outStruct = NaN;)
            %
            % category - string. some objects saves themself only with
            % specific category (image/experimetns/etc)
            
            outStruct = NaN;
        end
        
        function loadStateFromStruct(obj, savedStruct, category, subCategory) %#ok<*INUSD>
            % loads the state from a struct.
            % to support older versoins, always check for a value in the
            % struct before using it. view example in the first line.
            % category - a string, some savable objects will load stuff
            %            only for the 'image_lasers' category and not for
            %            'image_stages' category, for example
            % subCategory - string. could be empty string
            
            
            
            if isfield(savedStruct, 'some_value')
                obj.my_value = savedStruct.some_value;
            end
        end
        
        function string = returnReadableString(obj, savedStruct)
            % return a readable string to be shown. if this object
            % doesn't need a readable string, make (string = NaN;) or
            % (string = '');
            
            string = NaN;
        end
    end
    
end

