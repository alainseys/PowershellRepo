# Update the downloads

1. Navigate to citrix.com
2. Browse to Citrix download and find the url you want to download
3. Right-click the Download File button and choose Inspect. This will open the page in the browser DevTools.
Inspect might be called something else in other browsers. Inspect is what it's called in Edge and Chrome.
Alternatively you can just download the file and get the URL from the Downloads page in your browser. This is probably easier.
4. The DLNumber will be after http://downloads.citrix.com/ in the hyperlink. Should be a 5 digit number such as 20116.
5. The FileName will be after the DLNumber in the URL. For example the following is what to look for in the DevTools. This is for Multi-session OS Virtual Delivery Agent 2112 VDA.

``
<a href="javascript:void(0);" data-secureportal="true" class="ctx-dl-link ctx-photo" rel="https://secureportal.citrix.com/udl.asp?DLID=20116&amp;URL=https://downloads.citrix.com/20116/VDAServerSetup_2112.exe" id="downloadcomponent">
            <span class="icon-box-download"></span><span>Download File</span>
</a>
``
