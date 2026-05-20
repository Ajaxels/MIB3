# === Claude CLI ===
# work computer
claude mcp add --transport stdio matlab -- C:\hyapp\claude\matlab-mcp-core-server-win64.exe --initial-working-folder=c:\Matlab\MIB3\
# home computer
claude mcp add --transport stdio matlab -- c:\Users\Ilya\.local\bin\matlab-mcp-core-server-win64.exe --initial-working-folder=c:\Matlab\MIB3\

# === GitHub Copilot CLI WORK COMPUTER ===
# Add to %USERPROFILE%\.copilot\mcp-config.json:
# {
#   "mcpServers": {
#     "matlab": {
#       "type": "stdio",
#       "command": "C:\\hyapp\\claude\\matlab-mcp-core-server-win64.exe",
#       "args": ["--initial-working-folder=C:\\Matlab\\MIB3"]
#     }
#   }
# }