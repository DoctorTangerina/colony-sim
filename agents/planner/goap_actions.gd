class_name GoapActions
extends Node

const EAT := "Eat"
const REST := "Rest"
const PICKUP_FOOD := "PickupFood"
const PICKUP_WOOD := "PickupWood"
const DEPOSIT_RESOURCE := "DepositResource"
const RANDOM_EXPLORE := "RandomExplore"
const REPORT_RESOURCE := "ReportResource"
const REPORT_DEPLETION := "ReportDepletion"

## Base name for the grounded travel action (CONTEXT.md: GoTo). Never appears
## alone in a plan or a role config - the Planner grounds it into "GoTo[Kind]"
## instances (see GotoGrounding), and GoapActionExecutor dispatches on the
## "GoTo[" prefix rather than this exact name.
const GOTO := "GoTo"
