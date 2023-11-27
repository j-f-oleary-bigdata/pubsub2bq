

CREATE DATABASE MYSQL_DATABASENAME;
USE MYSQL_DATABASENAME;
CREATE TABLE MYSQL_TABLENAME (id INTEGER, first_name VARCHAR(255),
  last_name VARCHAR(255), email VARCHAR(255), zipcode INTEGER, city VARCHAR(255),
country VARCHAR(255),PRIMARY KEY(id));
    INSERT INTO MYSQL_TABLENAME (id, first_name, last_name,email,zipcode,city,country) 
    values (990, "Tom", "BagofDonuts","tom@corp.com", 2174 ,"Arlington","USA");
   INSERT INTO MYSQL_TABLENAME (id, first_name, last_name,email,zipcode,city,country) 
    values (991, "Phil", "BagofDonuts","phil@corp.com", 2174 ,"Arlington","USA");
INSERT INTO MYSQL_TABLENAME (id, first_name, last_name,email,zipcode,city,country) 
    values (992, "Ted", "BagofDonuts","ted@corp.com", 2174 ,"Arlington","USA");

