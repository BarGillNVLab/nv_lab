classdef (Abstract) Experiment < EventSender & EventListener & Savable
    %EXPERIMENT A generic experiment in the lab.
    % Abstract class for creating all other experiments.
    
    properties (Abstract, Constant)
        NAME
    end
    
    properties (SetAccess = protected)
        mCategory               % string. For loading (might change in subclasses)
       
        changeFlag = false;     % logical. True if changes have been made 
                                % in Experiment parameters, that require
                                % restarting the experiment
        
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
        laserOnDelay        %in us
        laserOffDelay       %in us
        mwOnDelay           %in us
        mwOffDelay          %in us
        detectionDuration   % detection windows, in us
    end
    
    properties (SetAccess = protected)
        signal              % double. Measured signal in the experiment (basically, unprocessed)
        timeout             % double. Time (in seconds) before experiment trial is marked as a fail
        currIter = 0;       % int. number of current iteration (average)
    end
    
    properties (SetAccess = {?Trackable, ?SpcmCounter})
        stopFlag = true;
        emergencyStopFlag = false;  % if true, we stop the experiment as soon as possible
        restartFlag = true;	% if true, then starting now the experiment will delete old data
        pausedAverage = false; 
    end
    
    properties (SetAccess = protected) % For plotting
        gAxes
        isPlotAlternate = false;
        
        % Default values, may be overridden by subclasses
        displayType1 = 'Unnormalized';
        displayType2 = 'Normalized';
    end
    
    properties (Constant)
        PATH_ALL_EXPERIMENTS = sprintf('%sControl code\\%s\\Experiment\\Experiments\\', ...
            PathHelper.getPathToNvLab(), PathHelper.SetupMode);
        PATH_CALIBRATIONS = [Experiment.PATH_ALL_EXPERIMENTS, 'Calibrations\']
        
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
        
        function obj = Experiment(name)
            Setup.init();       % In case no one has done this before
            
            obj@EventSender(name);
            obj@Savable(name);
            obj@EventListener({Tracker.NAME, StageScanner.NAME, SaveLoadCatExp.NAME});
            
            emptyValue = [];
            emptyUnits = '';
            obj.mCurrentXAxisParam = ExpParamDoubleVector('X axis', emptyValue, emptyUnits, obj.name);
            obj.mCurrentYAxisParam = ExpParamDoubleVector('Y axis', emptyValue, emptyUnits, obj.name);
            obj.signalParam = ExpResultDoubleVector('', emptyValue, emptyUnits, obj.name);
            
            obj.mCategory = Savable.CATEGORY_EXPERIMENTS; % will be overridden in Trackable
            
            % If we explicitly called the constructor, and did not get it
            % by its name, the old Experiment of this kind will be deleted
            oldObjOrNan = replaceBaseObject(obj);
            if isa(oldObjOrNan, 'Experiment')
                fprintf('Creating a new %s Experiment. All of its parameters were reset to default.\n', name)
            end
        end
        
        function cellOfStrings = getAllExpParameterProperties(obj)
            % Get all the property-names of properties from the
            % Experiment object that are from type "ExpParameter"
            allVariableProperties = obj.getAllNonConstProperties();
            isPropExpParam = cellfun(@(x) isa(obj.(x), 'ExpParameter'), allVariableProperties);
            cellOfStrings = allVariableProperties(isPropExpParam);
        end
        
        function robAndPausePrevious(obj, prevExp)
            % Copy parameters from previous experiment
            if isa(prevExp, 'Experiment') && isvalid(prevExp)
                prevExp.pause;
                
                % Get all the ExpParameter's from the previous experiment
                for paramNameCell = prevExp.getAllExpParameterProperties()
                    paramName = paramNameCell{:};
                    if isprop(obj, paramName)
                        % If the current experiment has this property also
                        obj.(paramName) = prevExp.(paramName);
                        obj.(paramName).expName = obj.name;  % expParam, I am (now) your parent!
                    end
                end
                
            else
                obj.sendError('Could not rob previous experiment - since it was not an experiment to begin with')
            end
        end

        
        function delete(obj) %#ok<INUSD>
            
            % We don't want to accidently save over current file
            sl = SaveLoad.getInstance(Savable.CATEGORY_EXPERIMENTS);
            sl.clearLocal;
        end
    end
       
    %% Setters
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
        
        function set.repeats(obj, newVal)
            obj.repeats = newVal;
            obj.changeFlag = true;  %#ok<MCSUP> % We need to update the PG
        end
        
    end
    
    %% Running
    methods
        function run(obj)
            %%% Primary function of class. Runs the Experiment.
            
            % This Experiment is running and is therefore the current one.
            obj.getSetCurrentExp(obj.NAME);
            
            % Before we start, we want to initialize all devices
            obj.prepare;
            if obj.changeFlag
                % We might not be able to continue with the old Experiment,
                % since something critical has changed
                obj.sendEventParamChanged;
                obj.changeFlag = false;
                
                % Dialog box
                strQuestion = sprintf('Critical parameters have been changed!\n Do you want to restart the Experiment?');
                strTitle = 'Parameters changed';
                if QuestionUserYesNo(strTitle, strQuestion)
                    obj.restartFlag = true;
                end
            end
            if obj.restartFlag
                % Resetting data
                obj.reset;
                obj.restartFlag = false;    % If we pause now, it will already be the middle of an experiment, and we want to be able to resume it.
                
                if obj.isTracking
                    tracker = getObjByName(Tracker.NAME);
                    if isempty(tracker); throwBaseObjException(Tracker.Name); end
                    trackablePos = tracker.getTrackable(TrackablePosition.NAME);
                    if ~trackablePos.isHistoryEmpty ...
                            && QuestionUserYesNo('Restart tracking?', 'Do you want to restart tracking?')
                        trackablePos.resetTrack
                    end
                end
            end
            
            % Starting
            GuiControllerExperiment(obj.name).start;
            
            obj.stopFlag = false;
            obj.emergencyStopFlag = false;  % In case we stopped the experiment abruptly
            sendEventExpResumed(obj);
            
            first = obj.currIter + 1;	% If we paused and did not restart, this is not 1
            
            for i = first : obj.averages
                obj.currIter = i;
                try
                    perform(obj);
                    plotResults(obj);
                    sendEventDataUpdated(obj)   % Saves, and maybe other things
                    percentage = i/obj.averages*100;
                    percision = log10(obj.averages);    % Enough percision, according to division result
                    fprintf('%.*f%%\n', percision, percentage)
                    
                    if obj.stopFlag
                        break
                    end
                catch err
                    obj.currIter = obj.currIter - 1; % This iteration did not succeed
                    err2warning(err)
                    break
                end
            end
            
            obj.pause;
            sendEventExpPaused(obj);
            obj.wrapUp;
        end
        
        function pause(obj)
            obj.stopFlag = true;
        end
        
        function emergencyStop(obj)
            obj.emergencyStopFlag = true;
            obj.pause;
        end
        
        function checkEmergencyStop(obj)
            drawnow     % Oddly, this causes us to change the value of obj.emergencyStopFlag RIGHT NOW, and not wait for the queue
            if obj.emergencyStopFlag
                obj.sendError('Experiment emergency stop!')
            end
        end
        
        function restart(obj)
            obj.restartFlag = true;
            obj.changeFlag = false;     % It doesn't matter, since we are restarting anyway
            obj.run;
        end
        
        function resetInternal(obj, nMeasPerRepeat)
            % All Experiments need this.
            %
            % nMeasPerRepeat -  number of times the sequence runs at
            %                   each repeat. Used to inform the user how
            %                   long the experiment is going to take.
            
            obj.signalParam.value = [];
            obj.signalParam2.value = [];
            obj.currIter = 0;
            obj.plotResults;     % Update the plot
            
            % Inform user
            pg = getObjByName(PulseGenerator.NAME);
            if isempty(pg); throwBaseObjException(PulseGenerator.Name); end
            seqTime = pg.sequence.duration * 1e-6; % Multiplication in 1e-6 is for converting usecs to secs.
            
            averageTime = obj.repeats * seqTime * nMeasPerRepeat;
            fprintf('Starting %d averages with each average taking %.1f seconds, on average.\n', ...
                obj.averages, averageTime);
        end
    end
    
    
    %% Defining the Experiment; to be overridden
    methods (Abstract, Access = protected)
        % Specifics of each of the experiments
        
        reset(obj)
        % (Re)initialize signal matrix and inform user we are starting anew
        
        prepare(obj) 
        % Initialize devices (SPCM, PulseGenerator, etc.)
        
        perform(obj)
        % Perform the main part of the experiment.
        
        wrapUp(obj)
    end
        
    %% Plotting
    methods
        function addGraphicAxes(obj, gAxes)
            % "Setter" for the axes, when they are created in the GUI
            if ~(isgraphics(gAxes) && isvalid(gAxes))
                obj.sendWarning('Graphic Axes were not created. Plotting is unavailable');
                return
            end
            obj.gAxes = gAxes;
        end

        function checkGraphicAxes(obj)
            if ~(isgraphics(obj.gAxes) && isvalid(obj.gAxes))
                % gAxes are no longer available, so we discard them
                obj.gAxes = [];
            end
        end
    end
    
    methods (Access = private)
        function savePlot(obj, folder, filename)
            % Saves the plot from the Experiment as .png and .fig files
            
            if isempty(obj.gAxes)
                return % Nothing to do here
                % todo: Maybe we want to plot and then save, whatever happens?
            end
            
            %%% Copy axes to an invisible figure
            figureInvis = AxesHelper.copyToNewFigure(obj.gAxes);
            
            %%% Get name for saving
            filename = PathHelper.removeDotSuffix(filename);
            fullpath = PathHelper.joinToFullPath(folder, filename);
            
            %%% Save image (.png)
            fullPathImage = [fullpath '.' ImageScanResult.IMAGE_FILE_SUFFIX];
            saveas(figureInvis, fullPathImage);
            
            %%% Save figure (.fig)
            % The figure is saved as invisible, but we set its creation
            % function to set it as visible
            set(figureInvis, 'CreateFcn', 'set(gcbo, ''Visible'', ''on'')'); % No other methods of specifying the function seemed to work...
            savefig(figureInvis, fullpath)
            
            %%% close the figure
            close(figureInvis);
        end
        
        function n = nDim(obj)
            % Helper function, to tell whether the experiment is 1D or 2D
            yAxisExists = ~isempty(obj.mCurrentYAxisParam.value);
            n = BooleanHelper.ifTrueElse(yAxisExists, 2, 1);
        end
    end
    
    methods (Access = {?Experiment, ?ViewExperimentPlot}) % Inclusion of ?Experiment gives access to its subclasses
        function plotResults(obj)
            % Plots the data in axes inside ViewExperimentPlot. Can be
            % overridden to allow for special kinds of plots, when an
            % Experiment requires that.
            
            if isempty(obj.gAxes)
                return
            end
            
            % Check whether we have anything to plot
            if obj.isPlotAlternate
                data = exp.alternateSignal().value;
            else
                data = obj.signalParam.value;
            end
            
            if isempty(data) || all(all(isnan(data)))
                % Default plot
                data = AxesHelper.DEFAULT_Y;
            end
            firstAxisVector = obj.mCurrentXAxisParam.value;
            secondAxisVector = obj.mCurrentYAxisParam.value; % Just in case we need it
            
            d = obj.nDim;
            
            if isempty(obj.gAxes.Children)
                % Nothing is plotted yet
                bottomLabel = obj.mCurrentXAxisParam.label;
                switch d
                    case 1
                        leftLabel = obj.signalParam.label;
                        AxesHelper.fill(obj.gAxes, data, d, ...
                            firstAxisVector, [], bottomLabel, leftLabel);
                    case 2
                        leftLabel = obj.mCurrentYAxisParam.label;
                        AxesHelper.fill(obj.gAxes, data, d, ...
                            firstAxisVector, secondAxisVector, bottomLabel, leftLabel);
                    otherwise
                        error('This shouldn''t have happenned!')
                end
                
                % Maybe this experiment shows more than one x/y-axis
                if ~isnan(obj.topParam)
                    AxesHelper.addAxisAcross(obj.gAxes, 'x', ...
                        obj.topParam.value, ...
                        obj.topParam.label)
                end
                if ~isnan(obj.rightParam)
                    AxesHelper.addAxisAcross(obj.gAxes, 'y', ...
                        obj.rightParam.value, ...
                        obj.rightParam.label)
                end
            else
                switch d
                    case 1
                        AxesHelper.update(obj.gAxes, data, d, firstAxisVector)
                    case 2
                        AxesHelper.update(obj.gAxes, data, d, firstAxisVector, secondAxisVector)
                end
            end
            
            if isa(obj.signalParam2, 'ExpParameter') && ~isempty(obj.signalParam2.value)
                % If there is more than one signal (Y) parameter, we want
                % to plot it above the first one,
                if ~obj.isPlotAlternate
                    % unless We are in alternative display mode.
                    data = obj.signalParam2.value;
                    AxesHelper.add(obj.gAxes, data, firstAxisVector)
                end
            end
            
        end
    end
    
    methods (Abstract, Access = protected)
        alternateSignal(obj)
        % Returns alternate view ("normalized") of the data, as an
        % ExpParam, if possible. If not, it returns an empty variable.
    end
    
    
    %% Overridden from EventListener
    methods
        % When events happen, this function jumps.
        % Event is the event sent from the EventSender
        function onEvent(obj, event)
            if strcmp(event.creator.name, SaveLoadCatExp.NAME) ...
                    && isfield(event.extraInfo, SaveLoad.EVENT_SAVE_SUCCESS_LOCAL_TO_FILE) ...
                    
                folder = event.extraInfo.(SaveLoad.EVENT_FOLDER);
                filename = event.extraInfo.(SaveLoad.EVENT_FILENAME);
                obj.savePlot(folder, filename);
                return
            end
            
            if isfield(event.extraInfo, StageScanner.EVENT_SCAN_STARTED)
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
            
            % We should save if either:
            %   @ This is the current Experiment
            %   @ This is a trackable
            shouldSave = (strcmp(category, Savable.CATEGORY_EXPERIMENTS) && strcmp(obj.NAME, obj.current)) ...
                || strcmp(category, Savable.CATEGORY_TRACKER);
            
            if shouldSave
                     % We only save the current Experiment
                if strcmp(type, Savable.TYPE_PARAMS)
                    outStruct = obj.saveParamsToStruct;     % Has default implementation. Might be overidden by subclasses.
                    outStruct.expName = obj.name;
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
            
            % Maybe we have double measurement
            sig2 = obj.signalParam2;
            if ~isempty(sig2) && ~isempty(sig2.value)
                outStruct.signalParam2 = sig2;
            end
        end
    end
    
    %% Helper functions
    methods
        function getDelays(obj)
            pg = getObjByName(PulseGenerator.NAME);
            if isempty(pg); throwBaseObjException(PulseGenerator.Name); end
            
            if isempty(obj.laserOnDelay) || isempty(obj.laserOffDelay)
                [obj.laserOnDelay, obj.laserOffDelay] = pg.channelName2Delays('greenLaser');
            end
            
            if isempty(obj.mwOnDelay) || isempty(obj.mwOffDelay)
                [obj.mwOnDelay, obj.mwOffDelay] = pg.channelName2Delays('MW');
            end
        end
        
        function tf = isRunning(obj)
            tf = ~obj.stopFlag;
        end
    end

    methods (Static, Access = protected)
        function s = getRawData(pg, spcm)
            spcm.startExperimentCount;
            pg.run;
            s = spcm.readFromExperiment;
            spcm.stopExperimentCount;
        end
    end
       
    methods (Access = protected)
        function [signal, sterr] = processData(obj, rawData)
            kc = 1e3;     % kilocounts
            musec = 1e-6;   % microseconds
            
            n = obj.repeats;
            m = length(rawData)/n;  % Number of reads each repeat
            s = (reshape(rawData, m, n))';
            
            signal = mean(s);
            signal = signal./(obj.detectionDuration*musec)/kc; %kcounts per second
            
            sterr = ste(s);
            sterr = sterr./(obj.detectionDuration*musec)/kc; % convert to kcps
        end
    end
    
    methods (Static, Access = private)
        function expName = getSetCurrentExp(newExperimentName)
            % "Static property" which stores the name of the experiment
            % currently running.
            % If given input, it will be saved as the new current
            % experiment name.
            persistent eName
            
            if exist('newExperimentName', 'var')
                if isa(newExperimentName, 'Experiment')
                    newExperimentName = newExperimentName.name;
                else
                    assert(ischar(newExperimentName))
                end
                
                eName = newExperimentName;
            elseif isempty(eName)
                eName = '';
            end
            
            expName = eName;
        end
    end

    methods (Static)
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
                % Get Callibration Experiments
                path2 = Experiment.PATH_CALIBRATIONS;
                [~, calibFileNames] = PathHelper.getAllFilesInFolder(path2, 'm');
                % Get Trackables
                path3 = Trackable.PATH_ALL_TRACKABLES;
                [~, trckblFileNames] = PathHelper.getAllFilesInFolder(path3, 'm');
                % Join
                expFileNames = [expFileNames, calibFileNames, trckblFileNames];
                
                % Extract names
                expClassNames = PathHelper.removeDotSuffix(expFileNames);
                expNames = cell(size(expFileNames));
                for i = 1:length(expFileNames)
                    % We extract the NAME property using an in-house
                    % function (which avoids using eval)
                    expNames{i} = getConstPropertyfromString(expClassNames{i}, 'NAME');
                end
                expNames{end+1} = SpcmCounter.NAME;     % todo: think about this
            end
            
            expNamesCell = expNames;
            expClassNamesCell = expClassNames;
        end
        
        function expName = current()
            % Public getter to private static property
            expName = Experiment.getSetCurrentExp();
        end
    end
        
    %% Saving & loading
    methods
        function save(obj, path)
            % Saves the experiment.
            % Three use cases - 
            % 1. no input argument (except obj): saves the file in the
            %    default folder, under a default name (e.g.
            %    'Echo_20180917_113506.mat')
            % 2. one extra argument - full path: saves the file as the path
            %    requested.
            % 3. one extra argument - folder name: saves the file at the
            %    specified folder, with the default name.
            
            
            % In order to save the Experiment which invoked this method, we
            % need to set it as The Current Experiment
            Experiment.getSetCurrentExp(obj.NAME);
            
            sl = SaveLoad.getInstance(Savable.CATEGORY_EXPERIMENTS);
            switch nargin
                case 1
                    % Use case 1
                    sl.save;
                case 2
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