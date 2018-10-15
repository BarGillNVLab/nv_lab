classdef ViewToy < ViewVBox & BaseObject
    %VIEWSPCM view for the SPCM counter
    % This view receives data from the SPCM counter, and displays it
    % according to the requirement of the user (especially, determinines
    % value for wrap (maximum number of data points presented). It can also
    % turn the the SPCMC on and off.
    properties
        input1_editText %input1
        input2_editText %input2
        total_pushbutton1 %pushButton
        answer_staticText %answer
        
    end
    properties (Constant)
        NAME = 'toy';
    end
    
    methods
        %% constructor
        % padding = 0;
        %spacing = 3;
        
        function obj = ViewToy(parent, controller, padding, specaing)
            obj@BaseObject(ViewToy.NAME);
            
            obj@ViewVBox(parent, controller,padding,specaing);
            
            vboxTitle = uix.HBox('Parent', obj.component);
            uix.Empty('Parent', vboxTitle);
            uicontrol(obj.PROP_TEXT_NO_BG{:}, 'Parent', vboxTitle, ...
                'String', 'ONE    CHANCE',...
            'FontSize',17);
            uix.Empty('Parent', vboxTitle);
            vboxTitle.Widths=([-1,100,-1]);
            
            
            
            
            vboxSecound = uix.HBox('Parent', obj.component);
            uix.Empty('Parent', vboxSecound);
            obj.input1_editText = uicontrol(obj.PROP_EDIT{:},...
                'Parent', vboxSecound,...
                'Callback',@(h,e)obj.edtTextCallback);
            uix.Empty('Parent', vboxSecound);
            uicontrol(obj.PROP_TEXT_NO_BG{:},...
                'Parent', vboxSecound, ...
                'String', '+',...
                'FontSize', 30);
            obj.input2_editText = uicontrol(obj.PROP_EDIT{:},...
                'Parent', vboxSecound,...
                'Callback',@(h,e)obj.edtText2Callback);
            uix.Empty('Parent', vboxSecound);
            uicontrol(obj.PROP_TEXT_NO_BG{:},...
                'Parent', vboxSecound, ...
                'String', '=',...
                'FontSize',30);
            obj.answer_staticText = uicontrol(obj.PROP_TEXT_NO_BG{:},...
                'Parent', vboxSecound);
            vboxSecound.Widths=([80,120,25,80,120,10,80,80]);
            
            
            vboxThird = uix.HBox('Parent', obj.component);
            uix.Empty('Parent', vboxThird);
            uicontrol(obj.PROP_BUTTON{:}, 'Parent', vboxThird, ...
                'String', 'total', ...
                'Callback', @obj.pushButtonCallback);
            uix.Empty('Parent', vboxThird);
            vboxThird.Widths=([-1,300,-1]);
            
            hboxButtons.Heights = [100,100,100];
            
            obj.height = 321;
            obj.width = 600;
            
        end
        
        function pushButtonCallback(obj, ~, ~)
            % eventdata  reserved - to be defined in a future version of MATLAB
            % handles    structure with handles and user data (see GUIDATA)
            a = get(obj.input1_editText,'String');
            b = get(obj.input2_editText,'String');
            % a and b are variables of Strings type, and need to be converted
            % to variables of Number type before they can be added together
            total = str2double(a) + str2double(b);
            c = num2str(total);
            % need to convert the answer back into String type to display it
            set(obj.answer_staticText,'String',c);
        end
        function edtTextCallback(obj)
            edtText=obj.input1_editText;
            if ~ValidationHelper.isStringValueANumber(edtText.String)
                edtText.String = '';
                EventStation.anonymousError('Only numbers can be accepted! Reverting.');
        
            end
        end
        
        function edtText2Callback(obj)
            edtText2=obj.input2_editText;
            if ~ValidationHelper.isStringValueANumber(edtText2.String)
                edtText2.String = '';
                EventStation.anonymousError('Only numbers can be accepted! Reverting.');
            
            end
        end
    end
    
  
    
    methods (Static)
        function init(parent, controller)
            aToy = ViewToy(parent,controller,3,3);
            addBaseObject(aToy);
        end
    end
end