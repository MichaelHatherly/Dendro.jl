#!/usr/bin/env bash
# Scalar-metric smells. Bash has no parameter list node, so parameter count is not
# exercised here. Two units, under the cohesion floor.

# dendro-expect: cyclomatic, cognitive_complexity, function_length, nesting_depth
classify() {
  local score=0
  if [ "$1" -gt 0 ]; then
    if [ "$2" -gt 0 ]; then
      if [ "$3" -eq 1 ]; then
        if [ "$4" -gt 100 ]; then
          if [ "$5" -gt 100 ]; then
            if [ "$6" -gt 100 ]; then
              if [ "$7" -gt 100 ]; then
                score=8
              else
                score=7
              fi
            else
              score=6
            fi
          else
            score=5
          fi
        elif [ "$4" -lt 100 ]; then
          score=4
        else
          score=3
        fi
      elif [ "$3" -eq 2 ]; then
        score=2
      elif [ "$3" -eq 3 ]; then
        score=1
      else
        score=0
      fi
    elif [ "$2" -lt 0 ]; then
      if [ "$3" -eq 1 ]; then
        score=-1
      elif [ "$3" -eq 2 ]; then
        score=-2
      else
        score=-3
      fi
    else
      score=0
    fi
  elif [ "$1" -lt 0 ]; then
    if [ "$2" -gt 0 ]; then
      if [ "$3" -eq 1 ]; then
        score=-4
      elif [ "$3" -eq 2 ]; then
        score=-5
      elif [ "$3" -eq 3 ]; then
        score=-6
      else
        score=-7
      fi
    elif [ "$2" -lt 0 ]; then
      if [ "$3" -eq 1 ]; then
        score=-8
      else
        score=-9
      fi
    else
      score=-10
    fi
  else
    score=$2
  fi
  local k=0
  while [ "$k" -lt 4 ]; do
    if [ "$k" -gt 100 ]; then
      score=$((score + 1))
    fi
    k=$((k + 1))
  done
  echo "$score"
}

# dendro-expect: boolean_complexity
eligible() {
  if [ "$1" -gt 0 ] && [ "$2" -gt 0 ] && [ "$3" -gt 0 ] && [ "$4" -gt 0 ] && [ "$1" -lt 100 ] && [ "$2" -lt 100 ] && [ "$3" -lt 100 ]; then
    echo 1
  else
    echo 0
  fi
}
