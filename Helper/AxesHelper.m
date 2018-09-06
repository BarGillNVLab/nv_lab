classdef AxesHelper
    %AXESHELPER Handles all plotting technicalities, with some added
    %options
    
    properties (Constant)
        DEFAULT_X = 0;
        DEFAULT_Y = NaN;
    end
    
    methods (Static)
        function fill(gAxes, data, dimNumber, firstAxisVector, secondAxisOptionalVector, bottomLabel, leftLabel, stdev)
            % Fills axes with data and labels
            % - usefull for displaying the scan results on GUI views
            %
            %
            % axesFig - a handle to a GUI axes() object
            % data - a 1D or 2D array of results
            % dimNumber - can be 1 or 2. easier to get it as an argument
            %               than calculate it every time with every func
            % firstAxisVector - vector to be shown as X axis in the figure
            % secondAxisOptionalVector - optional vector to be shown as Y
            % bottomLabel - string
            % leftLabel - string
            
            if ~any(dimNumber == [1,2])
                EventStation.anonymousWarning('Can''t understand and display %d-dimensional scan!', dimNumber);
                return
            end
            
            % We want to clear the slate
            gAxes.NextPlot = 'replace';
            if ~exist('stdev', 'var'); stdev = []; end
            
            % Plot and add labels
            AxesHelper.update(gAxes, data, dimNumber, firstAxisVector, secondAxisOptionalVector, stdev);
            xlabel(gAxes, bottomLabel);
            ylabel(gAxes, leftLabel);
            
            % 2D needs some special attention 
            if dimNumber == 2
                axis(gAxes, 'xy', 'tight', 'normal')
                axis(gAxes, 'manual')
                c = colorbar(gAxes, 'location', 'EastOutside');
                xlabel(c, 'kcps')
            end
            
            % Next plots should only change the lines/image in the plot
            gAxes.NextPlot = 'replacechildren';
            
        end
        
        function update(gAxes, data, dimNumber, firstAxisVector, secondAxisOptionalVector, stdev)
            % Change only the data in the axes, without changing labels and
            % other settings.
            %
            % Accepts data either as a vector (single plot) or as a cell of
            % vectors (multiple plots with the same x-vector)
            switch dimNumber
                case 1
                    if exist('stdev','var') && length(data)==length(stdev)
                        errorbar(gAxes, firstAxisVector, data, stdev);
                    else
                        plot(gAxes, firstAxisVector, data);
                    end
                case 2
                    % todo: add more data to image (e.g. std)
                    imagesc(data, 'Parent', gAxes, ...
                        'XData', firstAxisVector, ...
                        'YData', secondAxisOptionalVector);
                otherwise
                    EventStation.anonymousWarning('Can''t understand and display %d-dimensional scan!', dimNumber);
                    return
            end
        end
        
        function add(gAxes, data, firstAxisVector, stdev)
            % Plot one more curve on top of another/others. Only in 1D.
            gAxes.NextPlot = 'add';
            if exist('stdev','var') && length(data)==length(stdev)
                errorbar(gAxes, firstAxisVector, data, stdev);
            else
                plot(gAxes, firstAxisVector, data);
            end
            gAxes.NextPlot = 'replacechildren';
        end
        
        function clear(gAxes)
            % Clears the (graphic) axes by "filling" with nothing
            AxesHelper.fill(gAxes, obj.DEFAULT_Y, 1, obj.DEFAULT_X, [], '', '')
        end
        
        
        function leg = legend(gAxes, labels)
            % This function is introduced for the legend workaround
            % It creates legend in given axes with given labels, before any
            % data is given, so that displaying it later will nor reshuffle
            % the axes in view
            
            if ~exist('labels','var')
                labels = 'a';
            end
            
            warning off MATLAB:legend:IgnoringExtraEntries
            leg = legend(gAxes, labels, 'Location', 'northeast');
            leg.Visible = 'off';
            warning on MATLAB:legend:IgnoringExtraEntries
        end
    end
        
    methods (Static)
        %%% Add axes across %%%
        function gNewAxes = addAxisAcross(gAxes, axisLetter, ticks, label)
            % Adds an axis over given axis, with different ticks (or tick
            % labels, to the very least) and maybe a label
            %
            % gAxes - axes handle. The new ticks will be at the top of these axes.
            % axisLetter - either 'x' (for horizontal axis), 'y' (for
            %              vertical axis) or 'xy' (for both).
            % ticks - two options
            %         1. vector of doubles - requested ticks;
            %            Assumes ticks are given as column vector(s).
            %         2. function handle - transformation of the
            %            original axis.
            % label - label for the new axis.
            %
            % Returns:
            %   gNewAxes - handle to axes created by this function
            %
            %
            % Inspired by AddTopAxis() on MathWorks FileExchange
            %	Author : Emmanuel P. Dinnat
            %	Date : 09/2005
            %	Contact: emmanueldinnat@yahoo.fr
            
            % Create new axis from old one
            if ~ishandle(gAxes)
                error('Graphical axes handle is invalid!')
            end
            
            gNewAxes = axes('Position', gAxes.Position, ... position of first axes
                'XAxisLocation', 'top', ...
                'YAxisLocation','right');
            
            % Select NumericRuler (either X or Y)
            if length(axisLetter) == 1
                % that is, any string which is longer than 1 char will be
                % interpreted as 'xy'
                switch lower(axisLetter)
                    case 'x'
                        oldRuler = gAxes.XAxis;
                        newRuler = gNewAxes.XAxis;
                        % + Remove Y ticks
                        set(gNewAxes, 'yTickLabel', []);
                    case 'y'
                        oldRuler = gAxes.YAxis;
                        newRuler = gNewAxes.YAxis;
                        % + Remove X ticks
                        set(gNewAxes, 'xTickLabel', []);
                end
                AxesHelper.setTicks(oldRuler, newRuler, ticks);

                % Add label (if needed)
                if exist('label', 'var')
                    newRuler.Label = label;
                end
            else
                % "case 'xy'"
                AxesHelper.setTicks(gAxes.XAxis, gNewAxes.XAxis, ticks(:, 1));
                AxesHelper.setTicks(gAxes.YAxis, gNewAxes.YAxis, ticks(:, 2));
                
                % Add label (if needed)
                if exist('label', 'var')
                    gNewAxes.XAxis.Label = label{1};
                    gNewAxes.YAxis.Label = label{2};
                end
            end
            
            % We return gNewAxes, which were changed when we changed their
            % child NumericRuler
        end
        
        function setTicks(oldRuler, newRuler, ticks)
            % Create appropriate tick labels
            switch class(ticks)
                case {'double', 'cell'}
                    tickLen = length(ticks);
                    lim = oldRuler.Limits;
                    newRuler.TickValues = linspace(lim(1), lim(2), tickLen);
                    newRuler.TickLabels = ticks;
                    
                case 'function_handle'
                    tick_fun = ticks;
                    newAxisTicks = tick_fun(oldRuler.TickValues);
                    newRuler.TickLabels = num2str(newAxisTicks);
            end
        end
    end
end

