# NOTE Here we explicitly set LC_ALL to en_US so that we can use dot
# instead for a comma decimals

() {
  local cmd func
  for cmd in ${(kM)commands:#pw-*}
  do
    func="$cmd() { LC_ALL='en_US.UTF-8' command $cmd \$@ }"
    eval "$func"
  done
}
