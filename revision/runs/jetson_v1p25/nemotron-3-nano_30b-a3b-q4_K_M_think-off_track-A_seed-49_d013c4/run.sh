#!/usr/bin/env bash
set -euo pipefail

THREADS=4
mkdir -p results

samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

for sample in "${samples[@]}"; do
    bam="results/${sample}.bam"
    bai="results/${sample}.bam.bai"
    vcf="results/${sample}.vcf"
    vcf_gz="results/${sample}.vcf.gz"
    tbi="results/${sample}.vcf.gz.tbi"

    if [[ -e "$tbi" && "$tbi" -nt "${vcf}" ]]; then
        continue
    fi

    if [[ ! -e "$bam" || ! -e "$bai" ]]; then
        fq1="data/raw/${sample}_1.fq.gz"
        fq2="data/raw/${sample}_2.fq.gz"

        rg="@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA"

        bwa mem -t "$THREADS" -R "$rg" data/ref/chrM.fa "$fq1" "$fq2" |
            samtools sort -@ "$THREADS" -o "$bam"
    fi

    if [[ ! -e "$bai" ]]; then
        samtools index -@ "$THREADS" "$bam"
    fi

    if [[ ! -e "$vcf_gz" || ! -e "$tbi" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f data/ref/chrM.fa -o "$vcf" "$bam"

        bgzip -c "$vcf" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"

        rm -f "$vcf"
    fi
done

header="sample\tchrom\tpos\tref\talt\taf"
out_file="results/collapsed.tsv"

if [[ ! -e "$out_file" || any of the .vcf.gz files is newer than "$out_file" ]]; then
    {
        echo -e "$header"
        for sample in "${samples[@]}"; do
            bcftools query -f 'sample\t%CHROM\t%POS\t%REF\t%ALT\t%AF\n' \
                -r chrM:"1-$(wc -l < data/ref/chrM.fa)" \
                results/"${sample}.vcf.gz" | sed "s/^/${sample}\\t/"
        done
    } > "$out_file"
fi

exit 0