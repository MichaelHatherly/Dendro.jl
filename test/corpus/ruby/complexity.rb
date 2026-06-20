# Scalar-metric smells, each planted well past its band. Three units, under the
# cohesion floor.

SCALE = 100

# dendro-expect: cyclomatic, cognitive_complexity, function_length, nesting_depth
def classify(grid, x, y, mode)
  score = 0
  if x > 0
    if y > 0
      if mode == 1
        if grid[0] > SCALE
          if grid[1] > SCALE
            if grid[2] > SCALE
              if grid[3] > SCALE
                score += 8
              else
                score += 7
              end
            else
              score += 6
            end
          else
            score += 5
          end
        elsif grid[0] < SCALE
          score += 4
        else
          score += 3
        end
      elsif mode == 2
        score += 2
      elsif mode == 3
        score += 1
      else
        score = 0
      end
    elsif y < 0
      if mode == 1
        score -= 1
      elsif mode == 2
        score -= 2
      else
        score -= 3
      end
    else
      score = 0
    end
  elsif x < 0
    if y > 0
      if mode == 1
        score -= 4
      elsif mode == 2
        score -= 5
      elsif mode == 3
        score -= 6
      else
        score -= 7
      end
    elsif y < 0
      if mode == 1
        score -= 8
      else
        score -= 9
      end
    else
      score -= 10
    end
  else
    score += y
    score -= mode
  end
  k = 0
  while k < grid.length
    if grid[k] > SCALE
      score += 1
    elsif grid[k] < 0
      score -= 1
    end
    k = k + 1
  end
  while score > SCALE
    score -= SCALE
  end
  while score < -SCALE
    score += SCALE
  end
  score
end

# dendro-expect: parameter_count
def configure(a, b, c, d, e, f, g, h, i)
  a + b + c + d + e + f + g + h + i + SCALE
end

# dendro-expect: boolean_complexity
def eligible(a, b, c, d)
  a > 0 && b > 0 && c > 0 && d > 0 && a < SCALE && b < SCALE && c < SCALE
end
