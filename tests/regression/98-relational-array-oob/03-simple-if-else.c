//PARAM: --enable ana.arrayoob --enable ana.int.interval   --set ana.activated[+] apron   --set sem.int.signed_overflow assume_none 

int main()
{
	int len;
	int top;

	if(top) {
		len = 5;
	} else {
		len = 10;
	}

	char ptr[len];

	for(int i=0;i < len;i++) {
		char s  = ptr[i]; //NOWARN
	}
}

