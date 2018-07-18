function textnumber(no::Integer)
    n=copy(no)
    suffix=["one","two","three","four","five","six","seven","eight","nine"]
    prefix=["","twen","thir","four","fif","six","seven","eigh","nine"]
    numbertext=""
    0>n && (n=abs(n); numbertext*="negative ")
    0==n && (return "zero")
    n<10 && (return numbertext*suffix[n])
    n==10 && (return numbertext*"ten")
    n==11 && (return numbertext*"eleven")
    n==12 && (return numbertext*"twelve")
    tn=n-10
    tn<10 && (return numbertext*prefix[tn]*"teen")
    tn=round(Integer,fld(n,10))
    prefix[4]="for" # forty, not fourty (but fourteen, not forteen)
    tn<10 && (numbertext*=prefix[tn]*"ty"; tn=n-10tn; tn>0? (return numbertext*textnumber(tn)) : (return numbertext) )
    tn=round(Integer,fld(n,100))
    tn<10 && (numbertext*=suffix[tn]*" hundred"; tn=n-100tn; tn>0? (return numbertext*" "*textnumber(tn)) : (return numbertext) )
    pnm=["thousand";map(x->x*"illion",["m","b","tr","quadr","quint","sext","sept"])]
    pow=3:3:(3*length(pnm))
    for i=1:length(pow)
        tn=round(Integer,fld(n,10^pow[i]))
        if tn<10^3
            numbertext*=textnumber(tn)*" "*pnm[i]
            tn=n-tn*10^pow[i]
            if tn>0
                return numbertext*" "*textnumber(tn)
            else
                return numbertext
            end
        end
    end
    error("$no is too big for me to handle")
end

text_number(no)=replace(textnumber(no)," ","")
