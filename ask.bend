import Base

# A minimal stdin example: read one line, compare it to "YES".
#
#   bend ask.bend              # then type YES (or anything) + enter
#   printf "YES\n" | bend ask.bend
#
# Bend has no IO.read_line effect; a File handle on /dev/stdin is
# the way in. The handle is linear, so each read hands it back
# beside its result, and every value that must be inspected goes
# to a helper that matches on its parameter (a local let cannot be
# a match scrutinee in Bend).

def ask.reply(+line: String) -> String:
  # the answer to one line of input: "" means the input ended
  Bool.pick(String, String.is_empty(line), "the input ended",
    Bool.pick(String, String.eq(String.trim(line), "YES"), "you said YES", "you said something else"))

def ask.after(fr: File & Result<&1, &1, U32 & String, String>) -> IO(Unit):
  # the handle back beside the line it read, "" when the input ends
  (file, r) = fr
  IO.print(ask.reply(Result.default(&1, &1, U32 & String, String, r, "")) ++ "\n")

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("type YES and hit enter: ")
    stdin : File <- IO.try(File, File.open("/dev/stdin", "r"))
    fr : File & Result<&1, &1, U32 & String, String> <- File.read_line(stdin, 64)
    ask.after(fr)
