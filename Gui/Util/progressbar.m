function h = progressbar(varargin)
%uiwaitbar: A waitbar that can be embedded in a GUI figure.
%  Syntax and sample calling:
%    waitBarPosition = [20 20 200 20];  % Position of uiwaitbar in pixels
%    on your GUI.
%
%    handleToWaitBar = uiwaitbar(waitBarPosition);
%    for i = 1:100
%                percentageDone = i / 100;
%                uiwaitbar(handleToWaitBar, percentageDone)
%    end
%
% Adapted by Nadav Slotky, September 2018, 
%       from code by Doug Schwarz, 11 December 2008

        if ishandle(varargin{1})
                ax = varargin{1};
                value = varargin{2};
                p = get(ax,'Child');
                x = get(p,'XData');
                x(3:4) = value;
                set(p,'XData',x)
                return
        end

        pos = varargin{1};
        bg_color = [.3 .35 .4];        %'b';
        fg_color = [0 .5 0]; %'r';
        h = axes('Units','normalized',...
                'Position',pos,...
                'XLim',[0 1],'YLim',[0 1],...
                'XTick',[],'YTick',[],...
                'Color', bg_color,...
                'XColor', bg_color,'YColor', bg_color);
        patch([0 0 0 0], [0 1 1 0], fg_color,...
                'Parent', h,...
                'EdgeColor', 'none',...
                'EraseMode', 'none');