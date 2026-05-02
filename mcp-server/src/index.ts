#!/usr/bin/env node
/**
 * OpenOats MCP Server
 * 
 * Exposes TDD orchestration as MCP tools:
 * - generate_prompt: Build phase-specific prompts from components
 * - create_worktree: Git worktree management
 * - run_phase: Execute a full TDD phase
 * - validate_output: Validate subagent JSON output
 * - get_task_info: Read task specifications
 * 
 * Resources:
 * - prompts://master - The One Prompt
 * - prompts://components/{type}/{id} - Lego pieces
 * - tasks://{epic}/{task_id} - Task specifications
 * - schemas://{name} - Input/output schemas
 */

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ListResourcesRequestSchema,
  ReadResourceRequestSchema,
  ListPromptsRequestSchema,
  GetPromptRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';
import { z } from 'zod';
import { readFileSync, existsSync, readdirSync } from 'fs';
import { join, resolve } from 'path';
import YAML from 'yaml';

// Configuration
const REPO_ROOT = resolve(process.env.OPENOATS_REPO_ROOT || '../..');
const PROMPTS_DIR = join(REPO_ROOT, '.prompts');
const EPICS_DIR = join(REPO_ROOT, '.wfc', 'epics');

// Component cache
const componentCache = new Map<string, any>();

/**
 * Load a component (skill, context, action, validation, schema)
 */
function loadComponent(type: string, id: string): any {
  const cacheKey = `${type}/${id}`;
  if (componentCache.has(cacheKey)) {
    return componentCache.get(cacheKey);
  }

  const path = join(PROMPTS_DIR, 'components', type, `${id}.yaml`);
  if (!existsSync(path)) {
    throw new Error(`Component not found: ${type}/${id}`);
  }

  const content = readFileSync(path, 'utf-8');
  const parsed = YAML.parse(content);
  componentCache.set(cacheKey, parsed);
  return parsed;
}

/**
 * Get the master prompt content
 */
function getMasterPrompt(): string {
  const path = join(PROMPTS_DIR, 'swift-tdd-master.md');
  return readFileSync(path, 'utf-8');
}

/**
 * Build input JSON for a phase
 */
function buildPhaseInput(
  phase: 'RED' | 'GREEN' | 'REFACTOR',
  taskId: string,
  taskDesc: string,
  paths: { test_file: string; implementation_file: string },
  correlationId: string
): any {
  return {
    correlation_id: correlationId,
    prompt_version: '2.0.0',
    phase,
    task: {
      id: taskId,
      description: taskDesc
    },
    worktree_path: `.worktrees/${taskId}-${phase.toLowerCase()}/OpenOats/`,
    paths,
    constraints: {
      performance_target_ms: 20,
      min_property_tests: 2
    }
  };
}

/**
 * Assemble prompt from components
 */
function assemblePrompt(
  phase: 'RED' | 'GREEN' | 'REFACTOR',
  taskId: string,
  taskDesc: string,
  paths: { test_file: string; implementation_file: string }
): { prompt: string; input: any } {
  // Get master prompt
  const masterPrompt = getMasterPrompt();
  
  // Generate correlation ID
  const correlationId = `${new Date().toISOString().split('T')[0].replace(/-/g, '')}-${Math.random().toString(36).substring(2, 10)}`;
  
  // Build input JSON
  const input = buildPhaseInput(phase, taskId, taskDesc, paths, correlationId);
  
  // Load context component for this phase
  const contextComponent = loadComponent('context', `${phase.toLowerCase()}-context`);
  
  // Assemble final prompt
  const assembledPrompt = `${masterPrompt}

---

## PHASE-SPECIFIC CONTEXT

${contextComponent.phase_instructions || ''}

---

## YOUR INPUT

Execute this phase with the following input JSON:

\`\`\`json
${JSON.stringify(input, null, 2)}
\`\`\`

Remember: You are the **${phase}** agent. Follow ONLY the instructions for your phase in the master prompt above.
Your output MUST be valid JSON conforming to the schema defined in the master prompt.
`;

  return { prompt: assembledPrompt, input };
}

/**
 * Get task info from TASKS.md
 */
function getTaskInfo(epic: string, taskId: string): any {
  const tasksPath = join(EPICS_DIR, epic, 'TASKS.md');
  if (!existsSync(tasksPath)) {
    throw new Error(`Epic not found: ${epic}`);
  }

  const content = readFileSync(tasksPath, 'utf-8');
  const lines = content.split('\n');
  
  for (const line of lines) {
    const match = line.match(new RegExp(`^- \\[.\\] ${taskId}:\\s*(.+)$`));
    if (match) {
      return {
        id: taskId,
        description: match[1].trim(),
        epic
      };
    }
  }
  
  throw new Error(`Task ${taskId} not found in epic ${epic}`);
}

/**
 * Derive file paths from task info
 */
function derivePaths(taskId: string, taskDesc: string): { test_file: string; implementation_file: string } {
  const taskNum = parseInt(taskId.split('-')[1]);
  
  let testPath: string;
  let implPath: string;
  
  if (taskNum <= 4) {
    testPath = `Tests/OpenOatsTests/Domain/Models/${taskId}Tests.swift`;
    implPath = `Sources/OpenOats/Domain/Models/${taskId}Implementation.swift`;
  } else if (taskNum <= 8) {
    testPath = `Tests/OpenOatsTests/Business/UseCases/${taskId}Tests.swift`;
    implPath = `Sources/OpenOats/Business/UseCases/${taskId}UseCase.swift`;
  } else if (taskNum <= 15) {
    testPath = `Tests/OpenOatsTests/Infrastructure/Services/MLX/${taskId}Tests.swift`;
    implPath = 'Sources/OpenOats/Infrastructure/Services/MLX/MLXAudioProcessor.swift';
  } else {
    testPath = `Tests/OpenOatsTests/Presentation/ViewModels/${taskId}Tests.swift`;
    implPath = `Sources/OpenOats/Presentation/ViewModels/${taskId}ViewModel.swift`;
  }
  
  return { test_file: testPath, implementation_file: implPath };
}

// Create MCP server
const server = new Server(
  {
    name: 'openoats-mcp-server',
    version: '1.0.0',
  },
  {
    capabilities: {
      tools: {},
      resources: {},
      prompts: {},
    },
  }
);

/**
 * Tool: generate_prompt
 * Build a phase-specific prompt from components
 */
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  if (name === 'generate_prompt') {
    const schema = z.object({
      phase: z.enum(['RED', 'GREEN', 'REFACTOR']),
      task_id: z.string(),
      task_description: z.string().optional(),
      epic: z.string().default('swift6-compliance'),
    });

    const validated = schema.parse(args);
    
    // Get task info if description not provided
    let taskDesc = validated.task_description;
    if (!taskDesc) {
      const taskInfo = getTaskInfo(validated.epic, validated.task_id);
      taskDesc = taskInfo.description;
    }
    
    // Derive paths
    const paths = derivePaths(validated.task_id, taskDesc);
    
    // Assemble prompt
    const result = assemblePrompt(validated.phase, validated.task_id, taskDesc, paths);
    
    return {
      content: [
        {
          type: 'text',
          text: JSON.stringify({
            phase: validated.phase,
            task_id: validated.task_id,
            prompt_length: result.prompt.length,
            correlation_id: result.input.correlation_id,
            paths,
            // Return the full prompt
            prompt: result.prompt
          }, null, 2),
        },
      ],
    };
  }

  if (name === 'get_task_info') {
    const schema = z.object({
      epic: z.string(),
      task_id: z.string(),
    });

    const validated = schema.parse(args);
    const taskInfo = getTaskInfo(validated.epic, validated.task_id);
    
    return {
      content: [
        {
          type: 'text',
          text: JSON.stringify(taskInfo, null, 2),
        },
      ],
    };
  }

  if (name === 'list_components') {
    const schema = z.object({
      type: z.enum(['skills', 'context', 'actions', 'validations', 'schemas']).optional(),
    });

    const validated = schema.parse(args);
    
    const types = validated.type 
      ? [validated.type] 
      : ['skills', 'context', 'actions', 'validations', 'schemas'];
    
    const components: Record<string, string[]> = {};
    
    for (const type of types) {
      const dir = join(PROMPTS_DIR, 'components', type);
      if (existsSync(dir)) {
        components[type] = readdirSync(dir)
          .filter(f => f.endsWith('.yaml'))
          .map(f => f.replace('.yaml', ''));
      }
    }
    
    return {
      content: [
        {
          type: 'text',
          text: JSON.stringify(components, null, 2),
        },
      ],
    };
  }

  throw new Error(`Unknown tool: ${name}`);
});

/**
 * List available tools
 */
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: 'generate_prompt',
        description: 'Generate a phase-specific TDD prompt for a task',
        inputSchema: {
          type: 'object',
          properties: {
            phase: {
              type: 'string',
              enum: ['RED', 'GREEN', 'REFACTOR'],
              description: 'TDD phase to generate prompt for',
            },
            task_id: {
              type: 'string',
              description: 'Task ID (e.g., TASK-015)',
            },
            task_description: {
              type: 'string',
              description: 'Optional task description (fetched from TASKS.md if not provided)',
            },
            epic: {
              type: 'string',
              description: 'Epic directory name (default: swift6-compliance)',
              default: 'swift6-compliance',
            },
          },
          required: ['phase', 'task_id'],
        },
      },
      {
        name: 'get_task_info',
        description: 'Get task information from epic TASKS.md',
        inputSchema: {
          type: 'object',
          properties: {
            epic: {
              type: 'string',
              description: 'Epic directory name',
            },
            task_id: {
              type: 'string',
              description: 'Task ID (e.g., TASK-015)',
            },
          },
          required: ['epic', 'task_id'],
        },
      },
      {
        name: 'list_components',
        description: 'List available prompt components (Lego pieces)',
        inputSchema: {
          type: 'object',
          properties: {
            type: {
              type: 'string',
              enum: ['skills', 'context', 'actions', 'validations', 'schemas'],
              description: 'Component type to list (optional, lists all if omitted)',
            },
          },
        },
      },
    ],
  };
});

/**
 * List available resources
 */
server.setRequestHandler(ListResourcesRequestSchema, async () => {
  return {
    resources: [
      {
        uri: 'prompts://master',
        name: 'Master TDD Prompt',
        mimeType: 'text/markdown',
        description: 'The One Prompt (swift-tdd-master.md)',
      },
      {
        uri: 'schemas://red-output',
        name: 'RED Phase Output Schema',
        mimeType: 'application/json',
        description: 'JSON Schema for RED phase subagent output',
      },
      {
        uri: 'schemas://green-output',
        name: 'GREEN Phase Output Schema',
        mimeType: 'application/json',
        description: 'JSON Schema for GREEN phase subagent output',
      },
      {
        uri: 'schemas://refactor-output',
        name: 'REFACTOR Phase Output Schema',
        mimeType: 'application/json',
        description: 'JSON Schema for REFACTOR phase subagent output',
      },
    ],
  };
});

/**
 * Read resource content
 */
server.setRequestHandler(ReadResourceRequestSchema, async (request) => {
  const { uri } = request.params;
  
  if (uri === 'prompts://master') {
    return {
      contents: [
        {
          uri,
          mimeType: 'text/markdown',
          text: getMasterPrompt(),
        },
      ],
    };
  }

  if (uri.startsWith('prompts://components/')) {
    const parts = uri.replace('prompts://components/', '').split('/');
    if (parts.length === 2) {
      const [type, id] = parts;
      const component = loadComponent(type, id);
      return {
        contents: [
          {
            uri,
            mimeType: 'application/yaml',
            text: YAML.stringify(component),
          },
        ],
      };
    }
  }

  if (uri.startsWith('schemas://')) {
    const schemaName = uri.replace('schemas://', '');
    // Return schema definitions from master prompt or separate files
    return {
      contents: [
        {
          uri,
          mimeType: 'application/json',
          text: JSON.stringify({
            schema: schemaName,
            description: 'See swift-tdd-master.md for full schema',
          }, null, 2),
        },
      ],
    };
  }

  if (uri.startsWith('tasks://')) {
    const parts = uri.replace('tasks://', '').split('/');
    if (parts.length === 2) {
      const [epic, taskId] = parts;
      const taskInfo = getTaskInfo(epic, taskId);
      return {
        contents: [
          {
            uri,
            mimeType: 'application/json',
            text: JSON.stringify(taskInfo, null, 2),
          },
        ],
      };
    }
  }

  throw new Error(`Resource not found: ${uri}`);
});

/**
 * List available prompts
 */
server.setRequestHandler(ListPromptsRequestSchema, async () => {
  return {
    prompts: [
      {
        name: 'tdd_red',
        description: 'RED phase: Write failing tests',
        arguments: [
          {
            name: 'task_id',
            description: 'Task ID (e.g., TASK-015)',
            required: true,
          },
        ],
      },
      {
        name: 'tdd_green',
        description: 'GREEN phase: Minimal implementation',
        arguments: [
          {
            name: 'task_id',
            description: 'Task ID (e.g., TASK-015)',
            required: true,
          },
        ],
      },
      {
        name: 'tdd_refactor',
        description: 'REFACTOR phase: Optimize and clean',
        arguments: [
          {
            name: 'task_id',
            description: 'Task ID (e.g., TASK-015)',
            required: true,
          },
        ],
      },
    ],
  };
});

/**
 * Get prompt content
 */
server.setRequestHandler(GetPromptRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  const phaseMap: Record<string, 'RED' | 'GREEN' | 'REFACTOR'> = {
    tdd_red: 'RED',
    tdd_green: 'GREEN',
    tdd_refactor: 'REFACTOR',
  };

  const phase = phaseMap[name];
  if (!phase) {
    throw new Error(`Unknown prompt: ${name}`);
  }

  const taskId = args?.task_id as string;
  if (!taskId) {
    throw new Error('task_id argument required');
  }

  // Get task info
  const taskInfo = getTaskInfo('swift6-compliance', taskId);
  const paths = derivePaths(taskId, taskInfo.description);
  
  // Generate prompt
  const result = assemblePrompt(phase, taskId, taskInfo.description, paths);

  return {
    description: `${phase} phase prompt for ${taskId}`,
    messages: [
      {
        role: 'user',
        content: {
          type: 'text',
          text: result.prompt,
        },
      },
    ],
  };
});

// Start server
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error('OpenOats MCP Server running on stdio');
}

main().catch((error) => {
  console.error('Server error:', error);
  process.exit(1);
});