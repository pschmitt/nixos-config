# workstation — interactive desktop/laptop hosts (ge2, gk4, x13): the shared
# GUI + laptop + work base every personal machine runs.
{ ... }:
{
  imports = [
    ../common/global
    ../common/gui
    ../common/laptop
    ../common/work
    ../services/restic
  ];
}
