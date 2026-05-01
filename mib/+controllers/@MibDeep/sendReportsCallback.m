function sendReportsCallback(obj)
% SENDREPORTSCALLBACK - define parameters for sending progress report to the user's.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.sendReportsCallback()
%
% email address

    obj.SendReports.T_SendReports = obj.view.handles.T_SendReports.Value;
    if obj.SendReports.T_SendReports == 0; return; end

    prompts = {'Destination email:', ...
        'SMTP server address', 'SMTP server port', 'SMTP authentication', 'SMTP use starttls', ...
        'SMTP username', 'SMTP password', sprintf('Check to see the password\nin plain text after OK press'), ...
        'Send email when training is finished', sprintf('Send progress emails\n(defined by frequency of checkpoint saves)')};
    defAns = {obj.SendReports.TO_email, ...
        obj.SendReports.SMTP_server, obj.SendReports.SMTP_port, obj.SendReports.SMTP_auth, obj.SendReports.SMTP_starttls, ...
        obj.SendReports.SMTP_username, '**************', false, ...
        obj.SendReports.sendWhenFinished, obj.SendReports.sendDuringRun};
    dlgTitle = 'Send progress reports';
    options.helpBtnText = 'Test connection';
    options.Header = sprintf(['Use this dialog to specify settings for email notifications' ...
        'that are sent to your inbox.\nConnection can be checked by pressing ' ...
        'the "Test connection" button in the left bottom corner.' ...
        'To check connection reopen this dialog!']);
    options.HeaderLines = 3;
    options.WindowWidth = 630;
    options.WindowHeight = 430;
    options.LabelPosition = 'left';
    options.HelpUrl = sprintf('sendmail("%s", "Greetings from DeepMIB", "If you received this email, connection from DeepMIB to your email works fine!");', obj.SendReports.TO_email);
    answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts, defAns, dlgTitle, options);
    if isempty(answer); return; end

    obj.SendReports.TO_email = answer{1};
    obj.SendReports.SMTP_server = answer{2};
    obj.SendReports.SMTP_port = answer{3};
    obj.SendReports.SMTP_auth = logical(answer{4});
    obj.SendReports.SMTP_starttls = logical(answer{5});
    obj.SendReports.SMTP_username = answer{6};
    if ~strcmp(answer{7}, '**************')
        obj.SendReports.SMTP_password = answer{7};
    end
    if answer{8} % show password as text
        prompts2 = {'Here is the password for connection to SMTP server:'};
        defAns2 = {obj.SendReports.SMTP_password};
        options2.okBtnText = 'Update';
        options2.WindowWidth = 900;
        answer2 = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts2, defAns2, 'SMTP password', options2);
        if ~isempty(answer2); obj.SendReports.SMTP_password = answer2{1}; end
    end
    obj.SendReports.sendWhenFinished = logical(answer{9});
    obj.SendReports.sendDuringRun = logical(answer{10});

    % Apply prefs and props
    props = java.lang.System.getProperties;
    props.setProperty('mail.smtp.port', obj.SendReports.SMTP_port);
    if obj.SendReports.SMTP_auth
        props.setProperty('mail.smtp.auth', 'true');
    else
        props.setProperty('mail.smtp.auth', 'false');
    end
    if obj.SendReports.SMTP_starttls
        props.setProperty('mail.smtp.starttls.enable', 'true');
    else
        props.setProperty('mail.smtp.starttls.enable', 'false');
    end

    setpref('Internet','E_mail', obj.SendReports.TO_email);
    setpref('Internet','SMTP_Server', obj.SendReports.SMTP_server);
    setpref('Internet','SMTP_Username', obj.SendReports.SMTP_username);
    setpref('Internet','SMTP_Password', obj.SendReports.SMTP_password);

    %sendmail(obj.SendReports.TO_email, 'test', 'This is test');

end

