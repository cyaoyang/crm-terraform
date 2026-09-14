resource "aws_ses_email_identity" "sender" {
  email = "john.doe.joebank@gmail.com"
}

resource "aws_ses_email_identity" "law_firm_recipient" {
  email = "yylegalllc@outlook.com"
}