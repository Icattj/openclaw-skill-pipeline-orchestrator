#!/bin/bash
# pipeline-status.sh — Quick status check for pipeline state
# Usage: bash pipeline-status.sh [pipeline-id]

STATE_DIR="$HOME/.openclaw/workspace/state"

if [ -n "$1" ]; then
    PIPELINE_ID="$1"
    META_FILE="$STATE_DIR/pipeline-$PIPELINE_ID/meta.json"
else
    # Find most recent pipeline
    LATEST=$(ls -t "$STATE_DIR"/pipeline-*/meta.json 2>/dev/null | head -1)
    if [ -z "$LATEST" ]; then
        echo "No pipelines found in $STATE_DIR"
        exit 1
    fi
    META_FILE="$LATEST"
    PIPELINE_ID=$(basename $(dirname "$META_FILE") | sed 's/pipeline-//')
fi

if [ ! -f "$META_FILE" ]; then
    echo "Pipeline $PIPELINE_ID not found"
    exit 1
fi

PIPELINE_DIR=$(dirname "$META_FILE")

echo "═══════════════════════════════════════"
echo "  Pipeline: $PIPELINE_ID"
echo "═══════════════════════════════════════"

# Parse meta.json
if command -v jq &>/dev/null; then
    STATUS=$(jq -r '.status' "$META_FILE")
    STAGE=$(jq -r '.currentStage' "$META_FILE")
    TASK_COUNT=$(jq -r '.taskCount' "$META_FILE")
    PASSED=$(jq -r '.passedCount' "$META_FILE")
    FAILED=$(jq -r '.failedCount' "$META_FILE")
    FIX_ATTEMPTS=$(jq -r '.fixAttempts' "$META_FILE")
    CREATED=$(jq -r '.created' "$META_FILE")
    TASK_DESC=$(jq -r '.task' "$META_FILE" | head -c 80)
    
    echo "  Task:    $TASK_DESC"
    echo "  Status:  $STATUS"
    echo "  Stage:   $STAGE"
    echo "  Created: $CREATED"
    echo "───────────────────────────────────────"
    echo "  Tasks:   $TASK_COUNT total"
    echo "  Passed:  $PASSED"
    echo "  Failed:  $FAILED"
    echo "  Fix attempts: $FIX_ATTEMPTS / 3"
    echo "───────────────────────────────────────"
    
    # Show per-task progress if progress.json exists
    PROGRESS_FILE="$PIPELINE_DIR/progress.json"
    if [ -f "$PROGRESS_FILE" ]; then
        echo "  Task Status:"
        jq -r '.tasks | to_entries[] | "    \(.key): \(.value.status)"' "$PROGRESS_FILE"
    fi
else
    echo "  (install jq for formatted output)"
    cat "$META_FILE"
fi

echo "═══════════════════════════════════════"
echo "  State dir: $PIPELINE_DIR"
echo "  Files:"
ls -la "$PIPELINE_DIR"/ 2>/dev/null | grep -v total | awk '{print "    " $NF " (" $5 " bytes)"}'
echo "═══════════════════════════════════════"
