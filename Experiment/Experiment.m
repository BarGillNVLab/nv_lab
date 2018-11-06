classdef (Abstract) Experiment < EventSender & EventListener & Savable
    %EXPERIMENT A generic experiment in the lab.
    % Abstract class for creating all other experiments.
    
    properties (SetAccess = protected)
        mCategory               % string. For loading (might change in subclasses)
       
        changeFlag = true;      % logical. True if changes have been made 
                                % in Experiment parameters, but not yet
                                % uploaded to hardware
        
        mCurrentXAxisParam      % ExpParameter in charge of axis x (which has name and value)
        topParam                % Optional ExpParameter, parallel to the x axis parameter
        mCurrentYAxisParam		% ExpParameter in charge of axis y - maybe needed, but usually empty.
        rightParam              % Optional ExpParameter, parallel to the y axis parameter
        
        signalParam             % ExpParameter in charge of Experiment (raw) result (which has name and value)
        signalParam2            % ditto, for second optional raw result
    end
    
    properties
        averages            % int. Number of measurements to average from
        repeats             % int. Number of repeats per measurement
        isTracking          % logical. initialize tracking
        trackThreshhold     % double (between 0 and 1). Change in signal that will start the tracker
        laserInitializationDuration  % laser initialization in pulsed experiments
        shouldAutosave
    end
    
    properties (Access = protected)
        laserOnDelay = 0.1;  %in us
        laserOffDelay = 0.1; %in us
        mwOnDelay = 0.1;     %in us
        mwOffDelay = 0.1;    %in us
        detectionDuration   % detection windows, in \mus
    end
    
    properties (SetAccess = protected)
        signal              % double. Measured signal in the experiment (basically, unprocessed)
        timeout             % double. Time (in seconds) before experiment trial is marked as a fail
        currIter = 0;       % int. number of current iteration (average)
    end
    
    properties (SetAccess = {?Trackable, ?SpcmCounter})
        stopFlag = true;
        pauseFlag = false;	% false -> new signal will be acquired. true --> signal will be required.
        pausedAverage = false; 
    end
    
    properties (Abstract, Constant, Hidden)
        EXP_NAME        % char array. Name of experiment, as recognized by the system.
    end
    
    properties (Constant)
        NAME = 'Experiment'
        
        PATH_ALL_EXPERIMENTS = sprintf('%sControl code\\%s\\Experiment\\Experiments\\', ...
            PathHelper.getPathToNvLab(), PathHelper.SetupMode);
        
        EVENT_DATA_UPDATED = 'dataUpdated'      % when something changed regarding the plot (new data, change in x\y axis, change in x\y labels)
        EVENT_EXP_RESUMED = 'experimentResumed' % when the experiment is starting to run
        EVENT_EXP_PAUSED = 'experimentPaused'   % when the experiment stops from running
        EVENT_PLOT_ANALYZE_FIT = 'plot_analyzie_fit'        % when the experiment wants the plot to draw the fitting-function-analysis
        EVENT_PARAM_CHANGED = 'experimentParameterChanged'  % when one of the sequence params \ general params is changed
        
        % Exception handling
        EXCEPTION_ID_NO_EXPERIMENT = 'getExp:noExp';
        EXCEPTION_ID_NOT_CURRENT = 'getExp:notCurrExp';
    end
    
    methods
        function sendEventDataUpdated(obj); obj.sendEvent(struct(obj.EVENT_DATA_UPDATED, true)); end
        function sendEventExpResumed(obj); obj.sendEvent(struct(obj.EVENT_EXP_RESUMED, true)); end
        function sendEventExpPaused(obj); obj.sendEvent(struct(obj.EVENT_EXP_PAUSED, true)); end
        function sendEventPlotAnalyzeFit(obj); obj.sendEvent(struct(obj.EVENT_PLOT_ANALYZE_FIT, true)); end
        function sendEventParamChanged(obj); obj.sendEvent(struct(obj.EVENT_PARAM_CHANGED, true)); end
        
        function obj = Experiment()
            obj@EventSender(Experiment.NAME);
            obj@Savable(Experiment.NAME);
            obj@EventListener({Tracker.NAME, StageScanner.NAME});
            
            emptyValue = [];
            emptyUnits = '';
            obj.mCurrentXAxisParam = ExpParamDoubleVector('X axis', emptyValue, emptyUnits, obj.EXP_NAME);
            obj.mCurrentYAxisParam = ExpParamDoubleVector('Y axis', emptyValue, emptyUnits, obj.EXP_NAME);
            obj.signalParam = ExpResultDoubleVector('', emptyValue, emptyUnits, obj.EXP_NAME);
            
            obj.mCategory = Savable.CATEGORY_EXPERIMENTS; % will be overridden in Trackable
            
            obj.robAndKillPrevious;
            
        end
        
        function robAndKillPrevious(obj)
            % Copy parameters from previous experiment (if exists) and replace its base object
            try
                prevExp = getObjByName(Experiment.NAME);
                if isa(prevExp, 'Experiment') && isvalid(prevExp)
                    prevExp.pause;
                    obj.robExperiment(prevExp);
                end % No need to tell the user otherwise.
                delete(prevExp);
                replaceBaseObject(obj);
            catch
                % We got here if there was no Experiment here yet
                addBaseObject(obj);
            end
        end
        
        function cellOfStrings = getAllExpParameterProperties(obj)
            % Get all the property-names of properties from the
            % Experiment object that are from type "ExpParameter"
            allVariableProperties = obj.getAllNonConstProperties();
            isPropExpParam = cellfun(@(x) isa(obj.(x), 'ExpParameter'), allVariableProperties);
            cellOfStrings = allVariableProperties(isPropExpParam);
        end
        
        function robExperiment(obj, prevExperiment)
            % Get all the ExpParameter's from the previous experiment
            % prevExperiment = the previous experiment
            
            for paramNameCell = prevExperiment.getAllExpParameterProperties()
                paramName = paramNameCell{:};
                if isprop(obj, paramName)
                    % If the current experiment has this property also
                    obj.(paramName) = prevExperiment.(paramName);
                    obj.(paramName).expName = obj.EXP_NAME;  % expParam, I am (now) your parent!
                end
            end
        end
        
        function delete(obj) %#ok<INUSD>
            
            
            % We don't want to accidently save over current file
            sl = SaveLoad.getInstance(Savable.CATEGORY_EXPERIMENTS);
            sl.clearLocal;
        end
    end
       
    %% Setter
    methods
        %%% detectionDuration
        function checkDetectionDuration(obj, newVal)
            % Returns an error if property is invalid. To be overridden in
            % subclasses
            if ~isnumeric(newVal)
                obj.sendError('detectionDuration must be a number or a vector of numbers')
            end
        end
        
        function set.detectionDuration(obj, newVal)
            % MATLAB setter, that cannot be overridden in subclasses, per
            % MathWorks design. We therefore use checkDetectionDuration(),
            % which can be overridden.
            checkDetectionDuration(obj, newVal);
            % If we got here, then newVal is OK.
            obj.detectionDuration = newVal;
        end
        
    end
    
    %% Running
    methods
        function run(obj)
            %%% Primary function of class. Runs the Experiment.
            
            if ~obj.pauseFlag
                % Preparing
                clear(obj);
                % ^ If we have a previous Experiment that ran, it is time to delete the results, before they interfere with the current ones
                prepare(obj)
                obj.sendEventParamChanged;  % That happenned at preperation
                obj.pauseFlag = true;   % If we pause now, it will already be the middle of an experiment, and we can resume it.
            end
            
            % Starting
            GuiControllerExperimentPlot(obj.EXP_NAME).start;
            
            obj.stopFlag = false;
            sendEventExpResumed(obj);
            
            first = obj.currIter + 1;	% If we paused and did not restart, this is not 1
            
            for i = first : obj.averages
                obj.currIter = i;
                try
                    perform(obj);
                    sendEventDataUpdated(obj)   % Plots and saves
                    percentage = i/obj.averages*100;
                    percision = log10(obj.averages);    % Enough percision, according to division result
                    fprintf('%.*f%%\n', percision, percentage)
                    
                    if obj.stopFlag
                        sendEventExpPaused(obj);
                        return
                    end
                catch err
                    err2warning(err)
                    break
                end
            end
            
            obj.pauseFlag = false;
            obj.pause;
            sendEventExpPaused(obj);
        end
        
        function pause(obj)
            obj.stopFlag = true;
        end
        
        function restart(obj)
            obj.pauseFlag = false;
            obj.run;
        end
        
        function clear(obj)
            obj.mCurrentXAxisParam.value = [];
            obj.signalParam.value = [];
            obj.signalParam.value = [];
            obj.currIter = 0;
        end
    end
    
    %% To be overridden
    methods (Abstract)
        % Specifics of each of the experiments
        prepare(obj) 
        
        perform(obj)
        % Perform the main part of the experiment.
        
        wrapUp(obj)
        
        normalizedData(obj)
        % Returns ExpParams of the results from the experiment, after
        % normalization.
    end
    
    
    %% Overridden from EventListener
    methods
        % When events happen, this function jumps.
        % Event is the event sent from the EventSender
        function onEvent(obj, event)
            if isfield(event.extraInfo, Tracker.EVENT_TRACKER_FINISHED)
                obj.preapre;
                % After all events are done, we will be able to resume the experiments from where we stopped
            elseif isfield(event.extraInfo, StageScanner.EVENT_SCAN_STARTED)
                obj.pause;
            end
        end
    end
    
    
    %% Overridden from Savable
    methods (Access = protected)
        function outStruct = saveStateAsStruct(obj, category, type)
            % Saves the state as struct. If you want to save stuff, make
            % (outStruct = struct;) and put stuff inside. If you don't
            % want to save now, make (outStruct = NaN;)
            %
            % category - string. Some objects saves themself only with
            %                    specific category (image/experiments/etc.)
            % type - string.     Whether the objects saves at the beginning
            %                    of the run (parameter) or at its end (result)
            
            if strcmp(category, obj.mCategory) % mCategory is overrided by Tracker, and we need to check it
                if strcmp(type, Savable.TYPE_PARAMS)
                    outStruct = obj.saveParamsToStruct;     % Has default implementation. Might be overidden by subclasses.
                    outStruct.expName = obj.EXP_NAME;
                else
                    outStruct = obj.saveResultsToStruct;    % Has default implementation. Might be overidden by subclasses.
                end
            else
                outStruct = NaN;
            end
            
        end
        
        function loadStateFromStruct(obj, savedStruct, category, subCategory) %#ok<INUSD>
            % loads the state from a struct.
            % to support older versoins, always check for a value in the
            % struct before using it. view example in the first line.
            % category - a string, some savable objects will load stuff
            %            only for the 'image_lasers' category and not for
            %            'image_stages' category, for example
            % subCategory - string. could be empty string
            
            % mCategory is overrided by Tracker, and we need to check it
            if ~strcmp(category, obj.mCategory); return; end
            
            
            className = str2func(savedStruct.expName); % function handle for the class. We use @str2func, which is superior to @eval, when possible
            exp = className();
                
            for paramNameCell = exp.getAllExpParameterProperties()
                paramName = paramNameCell{:};
                if isfield(savedStruct, paramName)
                    % If the current experiment has this property also
                    exp.(paramName) = savedStruct.(paramName);
                end
            end
        end
        
        function string = returnReadableString(obj, savedStruct) %#ok<INUSD>
            % return a readable string to be shown. if this object
            % doesn't need a readable string, make (string = NaN;) or
            % (string = '');
            
            string = NaN;
        end
    end
    
    %% Default saving options for Experiment. Might be overridden by subclasses
    methods
        function outStruct = saveParamsToStruct(obj)
            for paramNameCell = obj.getAllExpParameterProperties()
                paramName = paramNameCell{:};
                outStruct.(paramName) = obj.(paramName);
            end
        end
        
        function outStruct = saveResultsToStruct(obj)
            outStruct.signalParam = obj.signalParam;
            outStruct.signalParam2 = obj.signalParam2;
        end
    end
    
    %% Helper functions
    methods
        function initialize(obj, numScans)
            spcm = getObjByName(Spcm.NAME);
            spcm.prepareReadByTime;
            spcm.setGatedCounting('', numScans);
            
            if isempty(obj.laserOnDelay) || isempty(obj.laserOffDelay)
                laser = getObjByName(LaserGate.GREEN_LASER_NAME);
                obj.laserOnDelay = laser.onDelay;
                obj.laserOffDelay = laser.offDelay;
            end
            
            if isempty(obj.mwOnDelay) || isempty(obj.mwOffDelay)
                mw = JsonInfoReader.getDefaultObject('frequencyGenerator');
                obj.mwOnDelay = mw.onDelay;
                obj.mwOffDelay = mw.offDelay;
            end
        end
        
        function tf = isRunning(obj)
            tf = ~obj.stopFlag;
        end
    end
    
    
    methods (Static)
        function obj = init()
            % Creates a default Experiment.
            try
                % Logic is reversed (without a clean way out):
                % if the try block succeeds, then we need to output a
                % warning.
                getObjByName(Experiment.NAME);
                EventStation.anonymousWarning('Deleting Previous experiment')
            catch
            end
            obj = ExperimentDefault;
        end
        
        function tf = current(newExpName)
            % logical. Whether the requested name is the current one (i.e.
            % obj.EXP_NAME).
            %
            % see also: GETEXPBYNAME
            try
                exp = getObjByName(Experiment.NAME);
                tf = strcmp(exp.EXP_NAME, newExpName);
            catch
                tf = false;
                EventStation.anonymousWarning('I don''t know the Experiment you asked for!');
            end
        end

        function [expNamesCell, expClassNamesCell] = getExperimentNames()
            %GETEXPERIMENTSNAMES returns cell of char arrays with names of
            %valid Experiments.
            % Algorithm: scan '\Experiments' folder, and get the Constant
            % property 'EXP_NAME' from each file (if exists). Add also
            % 'SpcmCounter', whatever be in the folder
            
            persistent expNames expClassNames
            if isempty(expNames)
                % Get 'regular' Experiments
                path = Experiment.PATH_ALL_EXPERIMENTS;
                [~, expFileNames] = PathHelper.getAllFilesInFolder(path, 'm');
                % Get Trackables
                path2 = Trackable.PATH_ALL_TRACKABLES;
                [~, trckblFileNames] = PathHelper.getAllFilesInFolder(path2, 'm');
                % Join
                expFileNames = [expFileNames, trckblFileNames];
                
                % Extract names
                expClassNames = PathHelper.removeDotSuffix(expFileNames);
                expNames = cell(size(expFileNames));
                for i = 1:length(expFileNames)
                    % We extract the EXP_NAME property using an in-house
                    % function (which avoids using eval)
                    expNames{i} = getConstPropertyfromString(expClassNames{i}, 'EXP_NAME');
                end
                expNames{end+1} = SpcmCounter.EXP_NAME;     % todo: think about this
            end
            
            expNamesCell = expNames;
            expClassNamesCell = expClassNames;
        end
    end
        
    %% Saving & loading
    methods (Static)
        function save(path)
            % Saves the experiment.
            % Three use cases - 
            % 1. no input argument: saves the file in the default folder,
            %    under a default name (e.g. 'Echo_20180917_113506.mat')
            % 2. one argument - full path: saves the file as the path
            %    requested.
            % 3. one argument - folder name: saves the file at the
            %    specified folder, with the default name.
            
            sl = SaveLoad.getInstance(Savable.CATEGORY_EXPERIMENTS);
            switch nargin
                case 0
                    % Use case 1
                    sl.save;
                case 1
                    filename = PathHelper.getFileNameFromFullPathFile(path);
                    if isempty(filename)
                        % Use case 3
                        path = PathHelper.joinToFullPath(path, sl.mLoadedFileName);
                    end
                    path = [PathHelper.removeDotSuffix(path), SaveLoad.SAVE_FILE_SUFFIX];  % Making sure there is proper suffix
                    sl.saveAs(path)
            end
        end
    end
    
end