"""Test if MCP server properly exposes tools via stdio protocol."""
import asyncio
import json
import sys
from server import mcp

async def test_tools_list():
    """Test if mcp.listtools() works"""
    print("Testing MCP server tool registration...", file=sys.stderr)
    
    try:
        tools = await mcp.list_tools()
        print(f"\nFound {len(tools)} tools:", file=sys.stderr)
        for tool in tools:
            name = tool.name if hasattr(tool, 'name') else str(tool)
            desc = tool.description if hasattr(tool, 'description') else ''
            print(f"  - {name}: {desc[:60]}", file=sys.stderr)
        
        tool_names = [t.name if hasattr(t, 'name') else str(t) for t in tools]
        if 'list_models' in tool_names:
            print("\n✓ list_models is registered!", file=sys.stderr)
        else:
            print("\n✗ list_models NOT found in registered tools!", file=sys.stderr)
            print(f"  Available tools: {tool_names}", file=sys.stderr)
        
        return tools
    except Exception as e:
        print(f"\n✗ Error listing tools: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
        return []

if __name__ == "__main__":
    tools = asyncio.run(test_tools_list())
    print(f"\n{len(tools)} tools registered", file=sys.stderr)
