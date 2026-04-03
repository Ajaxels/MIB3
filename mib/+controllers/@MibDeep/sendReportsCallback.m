function sendReportsCallback(obj)
    % function sendReportsCallback(obj)
    % define parameters for sending progress report to the user's
    % email address

    global mibPath;

    obj.SendReports.T_SendReports = obj.view.handles.T_SendReports.Value;
    if obj.SendReports.T_SendReports == 0; return; end

    prompts = {'Destination email:', ...
        'SMTP server address', 'SMTP server port', 'SMTP authentication', 'SMTP use starttls', ...
        'SMTP username', 'SMTP password', 'Check to see the password in plain text after OK press', ...
        'Send email when training is finished', 'Send progress emails (defined by frequency of checkpoint saves)'};
    defAns = {obj.SendReports.TO_email, ...
        obj.SendReports.SMTP_server, obj.SendReports.SMTP_port, obj.SendReports.SMTP_auth, obj.SendReports.SMTP_starttls, ...
        obj.SendReports.SMTP_username, '**************', false, ...
        obj.SendReports.sendWhenFinished, obj.SendReports.sendDuringRun};
    dlgTitle = 'Send progress reports';
    options.PromptLines = [1,1,1,1,1,1,1,2,2,2];
    options.WindowWidth = 1.4;
    options.helpBtnText = 'Test connection';
    options.Title = sprintf(['Use this dialog to specify settings for email notifications' ...
        'that are sent to your inbox.\nConnection can be checked by pressing ' ...
        'the "Test connection" button in the left bottom corner.' ...
        'To check connection reopen this dialog!']);
    options.TitleLines = 5;
    options.HelpUrl = sprintf('sendmail("%s", "Greetings from DeepMIB", "If you received this email, connection from DeepMIB to your email works fine!");', obj.SendReports.TO_email);
    answer = mibInputMultiDlg({mibPath}, prompts, defAns, dlgTitle, options);
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
        options2.WindowWidth = 2;
        answer2 = mibInputMultiDlg({mibPath}, prompts2, defAns2, 'SMTP password', options2);
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

