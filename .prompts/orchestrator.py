#!/usr/bin/env python3
#
# TDD Orchestrator - Tool-agnostic TDD pipeline manager
# "One prompt to rule them all, and in the darkness bind them"
#
# This orchestrator generates prompts for RED→GREEN→REFACTOR phases.
# It's tool-agnostic: works with Claude Code, Cursor, GitHub Copilot, etc.
#
# Usage modes:
#   --output-format=markdown    : Print full prompt to stdout (default)
#   --output-format=json       : Print JSON dispatch instructions
#   --output-dir=./prompts      : Write prompts to files
#   --execute                  : Actually dispatch (requires tool integration)
#

import json
import sys
import os
import uuid
import subprocess
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Any, Callable
from enum import Enum

class OutputFormat(Enum):
    MARKDOWN = "markdown"    # Full prompt text
    JSON = "json"           # Dispatch instructions
    FILES = "files"         # Write to files
    EXECUTE = "execute"     # Actually run (tool-specific)

class TDDOrchestrator:
    def __init__(self, repo_root: str):
        self.repo_root = Path(repo_root)
        self.prompts_dir = self.repo_root / ".prompts"
        self.master_prompt = self.prompts_dir / "swift-tdd-master.md"
        self.epic_dir = self.repo_root / ".wfc" / "epics" / "swift6-compliance"
        self.worktrees_dir = self.repo_root / ".worktrees"
        
    def generate_correlation_id(self) -> str:
        """Generate unique correlation ID for tracing."""
        return f"{datetime.now().strftime('%Y%m%d')}-{str(uuid.uuid4())[:8]}"
    
    def get_task_info(self, task_id: str) -> Dict[str, str]:
        """Read task from TASKS.md."""
        tasks_file = self.epic_dir / "TASKS.md"
        
        if not tasks_file.exists():
            raise FileNotFoundError(f"TASKS.md not found: {tasks_file}")
        
        content = tasks_file.read_text()
        
        # Find task entry - try multiple formats
        # Format 1: - [ ] TASK-015: Description...
        # Format 2: ## TASK-015: Description...
        # Format 3: A1[TASK-015: Description] in mermaid diagrams
        
        for line in content.split('\n'):
            # Check for checkbox format
            if f"{task_id}:" in line:
                # Try checkbox format
                if line.strip().startswith('- ['):
                    parts = line.split(':', 1)
                    if len(parts) == 2:
                        return {
                            'id': task_id,
                            'description': parts[1].strip(),
                            'line': line
                        }
                # Try heading format: ## TASK-015: Description
                elif line.strip().startswith(f'## {task_id}:'):
                    parts = line.split(':', 1)
                    if len(parts) == 2:
                        return {
                            'id': task_id,
                            'description': parts[1].strip(),
                            'line': line
                        }
        
        raise ValueError(f"Task {task_id} not found in TASKS.md")
    
    def derive_paths(self, task_id: str, task_desc: str) -> Dict[str, str]:
        """Infer file paths from task ID."""
        # Extract task number from various formats:
        # TASK-015 -> 15
        # TASK-SW6-015 -> 15
        # TASK-AUDIO-003 -> 3
        parts = task_id.split('-')
        task_num = int(parts[-1])  # Last part is the number
        
        # Path patterns based on task numbering
        if task_num <= 4:
            # Domain layer
            test_path = f"Tests/OpenOatsTests/Domain/Models/{task_id}Tests.swift"
            impl_path = f"Sources/OpenOats/Domain/Models/{task_id}Implementation.swift"
        elif task_num <= 8:
            # Business layer
            test_path = f"Tests/OpenOatsTests/Business/UseCases/{task_id}Tests.swift"
            impl_path = f"Sources/OpenOats/Business/UseCases/{task_id}UseCase.swift"
        elif task_num <= 15:
            # Infrastructure/MLX
            test_path = f"Tests/OpenOatsTests/Infrastructure/Services/MLX/{task_id}Tests.swift"
            impl_path = "Sources/OpenOats/Infrastructure/Services/MLX/MLXAudioProcessor.swift"
        else:
            # Presentation
            test_path = f"Tests/OpenOatsTests/Presentation/ViewModels/{task_id}Tests.swift"
            impl_path = f"Sources/OpenOats/Presentation/ViewModels/{task_id}ViewModel.swift"
        
        return {
            'test_file': test_path,
            'implementation_file': impl_path
        }
    
    def build_input_json(self, phase: str, correlation_id: str, task: Dict, paths: Dict) -> str:
        """Build JSON input for subagent."""
        input_data = {
            "correlation_id": correlation_id,
            "prompt_version": "2.0.0",
            "phase": phase,
            "task": {
                "id": task['id'],
                "description": task['description']
            },
            "worktree_path": f".worktrees/{task['id']}-{phase.lower()}/OpenOats/",
            "paths": paths,
            "constraints": {
                "performance_target_ms": 20,
                "min_property_tests": 2
            }
        }
        
        return json.dumps(input_data, indent=2)
    
    def create_worktree(self, task_id: str, phase: str) -> Path:
        """Create git worktree for phase."""
        branch = f"{task_id}-{phase.lower()}"
        worktree_path = self.worktrees_dir / branch / "OpenOats"
        
        # Determine base branch (feat!/3tier-clean-architecture -> main -> HEAD)
        # The integration branch for TDD workflow
        base_branch = "feat!/3tier-clean-architecture"
        result = subprocess.run(
            ["git", "rev-parse", "--verify", base_branch],
            cwd=self.repo_root,
            capture_output=True
        )
        if result.returncode != 0:
            base_branch = "main"
            result = subprocess.run(
                ["git", "rev-parse", "--verify", base_branch],
                cwd=self.repo_root,
                capture_output=True
            )
            if result.returncode != 0:
                base_branch = "HEAD"
        
        # Remove if exists (idempotent)
        if worktree_path.exists():
            subprocess.run(
                ["git", "worktree", "remove", str(worktree_path), "--force"],
                cwd=self.repo_root,
                capture_output=True
            )
            subprocess.run(
                ["git", "branch", "-D", branch],
                cwd=self.repo_root,
                capture_output=True
            )
        
        # Create from base branch
        subprocess.run(
            ["git", "worktree", "add", str(worktree_path), "-b", branch, base_branch],
            cwd=self.repo_root,
            check=True
        )
        
        return worktree_path
    
    def build_subagent_prompt(self, phase: str, input_json: str) -> str:
        """Build the full prompt for subagent."""
        master_content = self.master_prompt.read_text()
        
        prompt = f"""{master_content}

---

## YOUR INPUT FOR THIS RUN

Execute this phase with the following input JSON:

```json
{input_json}
```

Remember: You are the **{phase}** agent. Follow ONLY the instructions for your phase.
Your output MUST be valid JSON conforming to the schema defined in the master prompt.
"""
        
        return prompt
    
    def parse_output(self, output: str) -> Dict[str, Any]:
        """Parse JSON output from subagent."""
        try:
            # Find JSON in output (may have markdown fences)
            lines = output.strip().split('\n')
            json_start = None
            json_end = None
            
            for i, line in enumerate(lines):
                if line.strip() == '```json' or (json_start is None and line.strip().startswith('{')):
                    json_start = i if '```json' in line else i
                if json_start is not None and line.strip() == '```':
                    json_end = i
                    break
            
            if json_start is not None:
                if json_end:
                    json_str = '\n'.join(lines[json_start+1:json_end])
                else:
                    json_str = '\n'.join(lines[json_start:])
                return json.loads(json_str)
            
            # Try parsing entire output
            return json.loads(output)
        except json.JSONDecodeError as e:
            raise ValueError(f"Failed to parse subagent output as JSON: {e}")
    
    def run_phase(self, phase: str, correlation_id: str, task: Dict, paths: Dict, 
                  output_format: OutputFormat = OutputFormat.MARKDOWN,
                  output_dir: Optional[Path] = None,
                  execute_fn: Optional[Callable[[str], str]] = None) -> Dict[str, Any]:
        """Run/generate a single TDD phase."""
        
        print(f"\n{'='*60}", file=sys.stderr)
        print(f"  PHASE: {phase}", file=sys.stderr)
        print(f"  TASK: {task['id']}", file=sys.stderr)
        print(f"  CORRELATION: {correlation_id}", file=sys.stderr)
        print(f"{'='*60}\n", file=sys.stderr)
        
        # Create worktree
        worktree_path = self.create_worktree(task['id'], phase)
        print(f"[ORCH] Created worktree: {worktree_path}", file=sys.stderr)
        
        # Build input JSON
        input_json = self.build_input_json(phase, correlation_id, task, paths)
        
        # Build subagent prompt
        subagent_prompt = self.build_subagent_prompt(phase, input_json)
        
        # Handle output based on format
        if output_format == OutputFormat.MARKDOWN:
            # Print full prompt to stdout for copy-paste
            print(subagent_prompt)
            return {
                "status": "generated",
                "format": "markdown",
                "phase": phase,
                "task_id": task['id']
            }
        
        elif output_format == OutputFormat.JSON:
            # Print JSON dispatch instructions
            dispatch = {
                "tool": "ai-agent",
                "version": "1.0.0",
                "correlation_id": correlation_id,
                "phase": phase,
                "task": task,
                "prompt": subagent_prompt,
                "expected_output": "json",
                "output_schema": f"{phase.lower()}-output-schema",
                "worktree": str(worktree_path)
            }
            print(json.dumps(dispatch, indent=2))
            return {
                "status": "generated",
                "format": "json",
                "phase": phase,
                "task_id": task['id']
            }
        
        elif output_format == OutputFormat.FILES:
            # Write to files
            if output_dir is None:
                output_dir = Path(f"./generated-prompts/{task['id']}")
            
            output_dir.mkdir(parents=True, exist_ok=True)
            
            prompt_file = output_dir / f"{phase.lower()}-prompt.md"
            input_file = output_dir / f"{phase.lower()}-input.json"
            
            prompt_file.write_text(subagent_prompt)
            input_file.write_text(input_json)
            
            print(f"[ORCH] Prompt written to: {prompt_file}", file=sys.stderr)
            print(f"[ORCH] Input written to: {input_file}", file=sys.stderr)
            
            return {
                "status": "generated",
                "format": "files",
                "prompt_file": str(prompt_file),
                "input_file": str(input_file),
                "phase": phase,
                "task_id": task['id']
            }
        
        elif output_format == OutputFormat.EXECUTE:
            # Actually execute using provided function
            if execute_fn is None:
                raise ValueError("execute_fn required for EXECUTE format")
            
            print(f"[ORCH] Executing phase via provided function...", file=sys.stderr)
            output = execute_fn(subagent_prompt)
            
            # Parse output
            try:
                result = self.parse_output(output)
                return result
            except ValueError as e:
                return {
                    "status": "error",
                    "error": str(e),
                    "raw_output": output[:1000],
                    "phase": phase,
                    "task_id": task['id']
                }
    
    def next_phase(self, current: str) -> Optional[str]:
        """Get next phase in sequence."""
        phases = ["RED", "GREEN", "REFACTOR"]
        idx = phases.index(current)
        if idx < len(phases) - 1:
            return phases[idx + 1]
        return None
    
    def run(self, task_id: str, phases: List[str], 
            output_format: OutputFormat = OutputFormat.MARKDOWN,
            output_dir: Optional[Path] = None,
            execute_fn: Optional[Callable[[str], str]] = None) -> bool:
        """Run TDD cycle for task."""
        print(f"[ORCH] Starting TDD cycle for {task_id}", file=sys.stderr)
        print(f"[ORCH] Phases: {', '.join(phases)}", file=sys.stderr)
        print(f"[ORCH] Output format: {output_format.value}", file=sys.stderr)
        
        # Get task info
        task = self.get_task_info(task_id)
        paths = self.derive_paths(task_id, task['description'])
        
        print(f"[ORCH] Task: {task['description']}", file=sys.stderr)
        print(f"[ORCH] Test path: {paths['test_file']}", file=sys.stderr)
        print(f"[ORCH] Implementation path: {paths['implementation_file']}", file=sys.stderr)
        
        # Generate correlation ID
        correlation_id = self.generate_correlation_id()
        print(f"[ORCH] Correlation ID: {correlation_id}", file=sys.stderr)
        
        # Run each phase
        results = []
        for phase in phases:
            result = self.run_phase(
                phase, correlation_id, task, paths,
                output_format=output_format,
                output_dir=output_dir,
                execute_fn=execute_fn
            )
            results.append(result)
            
            if result.get('status') == 'error':
                print(f"[ORCH] ✗ Phase {phase} failed!", file=sys.stderr)
                return False
            
            if output_format == OutputFormat.EXECUTE:
                if result.get('status') == 'ok':
                    print(f"[ORCH] ✓ Phase {phase} complete", file=sys.stderr)
                else:
                    print(f"[ORCH] ⚠ Phase {phase} status: {result.get('status')}", file=sys.stderr)
            else:
                print(f"[ORCH] ✓ Phase {phase} generated", file=sys.stderr)
            
            # For non-execute modes, only generate first phase
            # User runs it, then comes back for next phase
            if output_format != OutputFormat.EXECUTE:
                print(f"\n[ORCH] Prompt generated for phase: {phase}", file=sys.stderr)
                print(f"[ORCH] Run this prompt in your AI tool, then return with output.", file=sys.stderr)
                break
        
        # Cleanup worktrees (only for EXECUTE mode with success)
        if output_format == OutputFormat.EXECUTE:
            if all(r.get('status') == 'ok' for r in results):
                print(f"[ORCH] Cleaning up worktrees...", file=sys.stderr)
                for phase in phases:
                    branch = f"{task_id}-{phase.lower()}"
                    worktree_path = self.worktrees_dir / branch / "OpenOats"
                    if worktree_path.exists():
                        subprocess.run(
                            ["git", "worktree", "remove", str(worktree_path), "--force"],
                            cwd=self.repo_root,
                            capture_output=True
                        )
                        subprocess.run(
                            ["git", "branch", "-D", branch],
                            cwd=self.repo_root,
                            capture_output=True
                        )
        
        return True


def main():
    import argparse
    
    parser = argparse.ArgumentParser(
        description='TDD Orchestrator - "One prompt to rule them all"',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate RED phase prompt (default: markdown to stdout)
  %(prog)s TASK-015 --red

  # Generate all phase prompts to files
  %(prog)s TASK-015 --all --output-format=files --output-dir=./prompts

  # Generate JSON dispatch instructions
  %(prog)s TASK-015 --red --output-format=json

  # Run full cycle (requires tool integration)
  %(prog)s TASK-015 --all --output-format=execute

Tool Integration:
  The orchestrator is tool-agnostic. It generates prompts that work with:
  - Claude Code (Anthropic)
  - Cursor (Anysphere)
  - GitHub Copilot
  - Custom AI tools

  Use --output-format=markdown to get the full prompt text for copy-paste.
  Use --output-format=json to get structured dispatch instructions.
  Use --output-format=files to write prompts to disk for batch processing.
  Use --output-format=execute with custom execute_fn for direct integration.
        """
    )
    parser.add_argument('task_id', help='Task ID (e.g., TASK-015)')
    parser.add_argument('--red', action='store_true', help='Run only RED phase')
    parser.add_argument('--green', action='store_true', help='Run only GREEN phase')
    parser.add_argument('--refactor', action='store_true', help='Run only REFACTOR phase')
    parser.add_argument('--all', action='store_true', help='Run all phases (default)')
    parser.add_argument('--output-format', 
                       choices=['markdown', 'json', 'files', 'execute'],
                       default='markdown',
                       help='Output format (default: markdown)')
    parser.add_argument('--output-dir', type=Path,
                       help='Output directory for files format')
    parser.add_argument('--repo-root', default='.', 
                       help='Repository root directory')
    
    args = parser.parse_args()
    
    # Determine phases to run
    phases = []
    if args.red:
        phases.append('RED')
    if args.green:
        phases.append('GREEN')
    if args.refactor:
        phases.append('REFACTOR')
    
    if not phases or args.all:
        phases = ['RED', 'GREEN', 'REFACTOR']
    
    # Map output format
    format_map = {
        'markdown': OutputFormat.MARKDOWN,
        'json': OutputFormat.JSON,
        'files': OutputFormat.FILES,
        'execute': OutputFormat.EXECUTE
    }
    output_format = format_map[args.output_format]
    
    # Run orchestrator
    orchestrator = TDDOrchestrator(args.repo_root)
    success = orchestrator.run(
        args.task_id, 
        phases,
        output_format=output_format,
        output_dir=args.output_dir
    )
    
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()