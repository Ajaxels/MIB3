function skipQuotedGroup(fid)
% SKIPQUOTEDGROUP - Consume an AmiraMesh header group whose opening brace was already read.
%
% Syntax:
%   .. code-block:: matlab
%
%      io.AmiraMesh.skipQuotedGroup(fid)
%
% Reads lines from ``fid`` until the brace opened on the current line is closed
% again, counting only braces that are **outside** double-quoted strings.
%
% This exists because Amira's ``HistoryLogHead`` group cannot be skipped by the
% line-by-line brace counting used for the rest of the header: its ``ModuleState``
% entries are multi-line quoted strings that contain unbalanced braces and even the
% keyword ``Lattice``. Counting those braces drifts the nesting level, and the
% ``Lattice`` occurrence terminates the Parameters loop early - which left the
% parameter list completely empty for files exported by Amira's Extract Subvolume.
%
% The quote state is deliberately carried across lines, because such a string may
% span many of them; a backslash escapes the character that follows it.
%
% Input Arguments:
%   - **fid** - [numeric] file identifier positioned just after the group's ``{``
%
% Output Arguments:
%   (none) - ``fid`` is left positioned just after the group's matching ``}``
%

groupDepth = 1;
insideString = false;
while groupDepth > 0
    tline = fgetl(fid);
    if ~ischar(tline); return; end      % unexpected end of file
    charIndex = 1;
    while charIndex <= numel(tline)
        currentChar = tline(charIndex);
        if insideString
            if currentChar == '\'
                charIndex = charIndex + 2;  % skip the escaped character
                continue;
            elseif currentChar == '"'
                insideString = false;
            end
        else
            switch currentChar
                case '"'; insideString = true;
                case '{'; groupDepth = groupDepth + 1;
                case '}'
                    groupDepth = groupDepth - 1;
                    if groupDepth == 0; return; end
            end
        end
        charIndex = charIndex + 1;
    end
end
end
