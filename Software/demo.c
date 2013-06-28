#include <stdio.h>

#include <propeller.h>
#include <cog.h>

#include "p6502_feature.h"
#include "p6502_hw.h"
#include "p6502_control.h"

void main(void)
{
  p6502_control_init();

  p6502_control_main(0, 0, NULL);
}