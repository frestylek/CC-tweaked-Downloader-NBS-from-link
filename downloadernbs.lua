local answer 
repeat
   io.write("Podaj link grubasie? ")
   io.flush()
   answer=io.read()
until answer~= nil
local name
repeat
   io.write("Podaj nazwe? ")
   io.flush()
   name=io.read()
until name~= nil
 
if answer ~= nil and name ~= nil then
  local w = http.get(answer,nil,true)
  test = fs.open(name .. ".nbs","wb")
  test.write(w.readAll())
  test.close()
end
